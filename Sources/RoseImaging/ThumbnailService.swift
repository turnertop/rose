import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import RoseCore

public enum ThumbnailPriority: Int, Comparable, Sendable {
    case prefetch, visible, preview
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    fileprivate var operationPriority: Operation.QueuePriority { self == .prefetch ? .veryLow : .high }
}

/// A subscriber's cancellation never cancels another cell's request for the same image.
public final class ThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var onCancel: (() -> Void)?

    fileprivate init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let action = onCancel; onCancel = nil
        lock.unlock()
        action?()
    }
    fileprivate func finish() { lock.lock(); onCancel = nil; lock.unlock() }
}

public struct ThumbnailMetrics: Sendable {
    public init() {}
    public fileprivate(set) var requests = 0
    public fileprivate(set) var coalesced = 0
    public fileprivate(set) var cancelled = 0
    public fileprivate(set) var memoryHits = 0
    public fileprivate(set) var diskHits = 0
    public fileprivate(set) var sourceDecodes = 0
    public fileprivate(set) var decodeMilliseconds = 0.0
    public fileprivate(set) var pendingJobs = 0
    public fileprivate(set) var peakJobs = 0
    public fileprivate(set) var diskWrites = 0
    public fileprivate(set) var skippedWrites = 0
    public fileprivate(set) var maxDeliveryBatch = 0
}

public enum ThumbnailSize {
    /// Stable buckets avoid generating a new disk entry for every slider/window pixel.
    public static func pixels(width: CGFloat, height: CGFloat, scale: CGFloat) -> Int {
        guard width.isFinite, height.isFinite, scale.isFinite, width > 0, height > 0, scale > 0 else { return 640 }
        let needed = max(width, height) * scale
        return [160, 320, 640, 1024, 1600].first { CGFloat($0) >= needed } ?? 1600
    }
}

/// No source I/O, compressed-image decoding, or cache encoding runs on the UI thread.
public final class ThumbnailService: @unchecked Sendable {
    public static let shared = ThumbnailService()
    private let gridMemory = NSCache<NSString, CGImage>()
    private let previewMemory = NSCache<NSString, CGImage>()
    private let lookupQueue: OperationQueue
    private let decodeQueue: OperationQueue
    private let diskQueue: OperationQueue
    private let cacheDirectory: URL
    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private var measurements = ThumbnailMetrics()
    private var rapidScrollClients: Set<UUID> = []
    private var pendingWriteKeys: Set<String> = []
    private var pendingWriteBytes = 0
    private var lastTrim = Date.distantPast // accessed only on the serial disk queue
    private var deliveries: [Delivery] = []
    private var deliveryScheduled = false

    private struct Subscriber {
        let token: ThumbnailRequest
        let priority: ThumbnailPriority
        let completion: ((CGImage?) -> Void)?
    }
    private final class Job {
        let key: String
        let asset: ImageAsset
        let pixels: Int
        var subscribers: [UUID: Subscriber] = [:] // guarded by the service lock
        var operation: Operation?
        init(key: String, asset: ImageAsset, pixels: Int) { self.key = key; self.asset = asset; self.pixels = pixels }
        var priority: ThumbnailPriority { subscribers.values.map(\.priority).max() ?? .prefetch }
    }
    private struct Delivery {
        let subscriber: Subscriber
        let image: CGImage?
    }

    public init(cacheDirectory: URL? = nil, lookupQueue: OperationQueue? = nil,
                decodeQueue: OperationQueue? = nil, diskQueue: OperationQueue? = nil) {
        let base = ProcessInfo.processInfo.environment["ROSE_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Rose")
        self.cacheDirectory = cacheDirectory ?? base.appendingPathComponent("Thumbnails", isDirectory: true)
        self.lookupQueue = lookupQueue ?? OperationQueue()
        self.decodeQueue = decodeQueue ?? OperationQueue()
        self.diskQueue = diskQueue ?? OperationQueue()
        self.lookupQueue.name = "app.rose.thumbnail-cache"; self.lookupQueue.maxConcurrentOperationCount = 2
        self.lookupQueue.qualityOfService = .userInitiated
        self.decodeQueue.name = "app.rose.thumbnail-decode"; self.decodeQueue.maxConcurrentOperationCount = 2
        self.decodeQueue.qualityOfService = .userInitiated
        self.diskQueue.name = "app.rose.thumbnail-write"; self.diskQueue.maxConcurrentOperationCount = 1
        self.diskQueue.qualityOfService = .utility
        gridMemory.totalCostLimit = 80 * 1024 * 1024; gridMemory.countLimit = 450
        previewMemory.totalCostLimit = 20 * 1024 * 1024; previewMemory.countLimit = 4
    }

    @discardableResult
    public func load(_ asset: ImageAsset, maxPixel: Int = 640, priority: ThumbnailPriority = .visible,
                     completion: ((CGImage?) -> Void)? = nil) -> ThumbnailRequest {
        let pixels = max(1, min(1800, maxPixel))
        let key = signature(asset, pixels: pixels)
        let subscriberID = UUID()
        let token = ThumbnailRequest { [weak self] in self?.cancel(key: key, subscriberID: subscriberID) }
        let subscriber = Subscriber(token: token, priority: priority, completion: completion)
        lock.lock()
        measurements.requests += 1
        if let job = jobs[key] {
            job.subscribers[subscriberID] = subscriber
            job.operation?.queuePriority = job.priority.operationPriority
            measurements.coalesced += 1
            lock.unlock()
        } else {
            let job = Job(key: key, asset: asset, pixels: pixels)
            job.subscribers[subscriberID] = subscriber
            jobs[key] = job
            measurements.peakJobs = max(measurements.peakJobs, jobs.count)
            lock.unlock()
            schedule(job, on: lookupQueue) { [weak self] job, operation in self?.lookup(job, operation: operation) }
        }
        return token
    }

    public func setRapidScrolling(_ rapid: Bool, client: UUID) {
        lock.lock()
        if rapid { rapidScrollClients.insert(client) } else { rapidScrollClients.remove(client) }
        let concurrency = rapidScrollClients.isEmpty ? 2 : 1
        if decodeQueue.maxConcurrentOperationCount != concurrency { decodeQueue.maxConcurrentOperationCount = concurrency }
        lock.unlock()
    }

    public func metrics() -> ThumbnailMetrics {
        lock.lock(); defer { lock.unlock() }
        var result = measurements; result.pendingJobs = jobs.count
        return result
    }
    public func clearMemory() { gridMemory.removeAllObjects(); previewMemory.removeAllObjects() }
    public func waitForCacheWrites() async {
        await withCheckedContinuation { continuation in diskQueue.addBarrierBlock { continuation.resume() } }
    }

    private func signature(_ asset: ImageAsset, pixels: Int) -> String {
        // Keep the existing disk-cache version so 640px thumbnails survive this upgrade.
        "v2|\(asset.id)|\(asset.modifiedAt.timeIntervalSince1970)|\(asset.byteSize)|\(pixels)"
    }
    private func cacheURL(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("thumb")
    }
    private func memory(for pixels: Int) -> NSCache<NSString, CGImage> { pixels > 1600 ? previewMemory : gridMemory }

    private func schedule(_ job: Job, on queue: OperationQueue, action: @escaping (Job, BlockOperation) -> Void) {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak job, weak operation] in
            guard let job, let operation, !operation.isCancelled else { return }
            autoreleasepool { action(job, operation) }
        }
        lock.lock()
        guard jobs[job.key] === job else { lock.unlock(); return }
        operation.queuePriority = job.priority.operationPriority
        job.operation = operation
        lock.unlock()
        queue.addOperation(operation)
    }

    private func lookup(_ job: Job, operation: Operation) {
        // Even warm-cache requests validate source availability, away from the main thread.
        guard FileManager.default.isReadableFile(atPath: job.asset.id) else { complete(job, image: nil); return }
        guard !operation.isCancelled else { return }
        if let image = memory(for: job.pixels).object(forKey: job.key as NSString) {
            lock.lock(); measurements.memoryHits += 1; lock.unlock()
            complete(job, image: image)
            return
        }
        // Larger existing thumbnails can seed a smaller size without reopening the original.
        let sizes = [job.pixels] + [160, 320, 640, 1024, 1600, 1800].filter { $0 > job.pixels }
        for pixels in sizes {
            guard !operation.isCancelled else { return }
            let url = cacheURL(signature(job.asset, pixels: pixels))
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let image = Self.decode(url, pixels: job.pixels) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            lock.lock(); measurements.diskHits += 1; lock.unlock()
            cache(image, for: job)
            if pixels != job.pixels { persist(image, key: job.key) }
            complete(job, image: image)
            return
        }
        schedule(job, on: decodeQueue) { [weak self] job, operation in self?.decodeSource(job, operation: operation) }
    }

    private func decodeSource(_ job: Job, operation: Operation) {
        guard !operation.isCancelled else { return }
        let start = ProcessInfo.processInfo.systemUptime
        let image = Self.decode(job.asset.url, pixels: job.pixels)
        lock.lock()
        measurements.sourceDecodes += 1
        measurements.decodeMilliseconds += (ProcessInfo.processInfo.systemUptime - start) * 1000
        let wanted = jobs[job.key] === job
        lock.unlock()
        guard !operation.isCancelled, wanted else { return }
        if let image { cache(image, for: job); persist(image, key: job.key) }
        complete(job, image: image)
    }

    private static func decode(_ url: URL, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary),
              let fallbackSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let colorSpace = decoded.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? fallbackSpace
        let opaque = [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(decoded.alphaInfo)
        let alpha = opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst
        guard
              let context = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue) else { return nil }
        // Force decompression and a predictable bitmap format while preserving RGB profiles.
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        return context.makeImage()
    }

    private func cache(_ image: CGImage, for job: Job) {
        memory(for: job.pixels).setObject(image, forKey: job.key as NSString, cost: image.bytesPerRow * image.height)
    }

    private func cancel(key: String, subscriberID: UUID) {
        lock.lock()
        measurements.cancelled += 1
        guard let job = jobs[key] else { lock.unlock(); return }
        job.subscribers.removeValue(forKey: subscriberID)
        let operation = job.operation
        let empty = job.subscribers.isEmpty
        if empty { jobs.removeValue(forKey: key) }
        else { operation?.queuePriority = job.priority.operationPriority }
        lock.unlock()
        if empty { operation?.cancel() }
    }

    private func complete(_ job: Job, image: CGImage?) {
        lock.lock()
        guard jobs[job.key] === job else { lock.unlock(); return }
        jobs.removeValue(forKey: job.key)
        for subscriber in job.subscribers.values {
            subscriber.token.finish()
            if subscriber.completion != nil { deliveries.append(Delivery(subscriber: subscriber, image: image)) }
        }
        let schedule = !deliveryScheduled && !deliveries.isEmpty
        if schedule { deliveryScheduled = true }
        lock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.deliver() } }
    }

    private func deliver() {
        // Bound image installation bursts. The first batch has no deliberate delay.
        lock.lock()
        deliveries.sort { $0.subscriber.priority > $1.subscriber.priority }
        let batch = Array(deliveries.prefix(4)); deliveries.removeFirst(batch.count)
        measurements.maxDeliveryBatch = max(measurements.maxDeliveryBatch, batch.count)
        lock.unlock()
        for delivery in batch where !delivery.subscriber.token.isCancelled {
            delivery.subscriber.completion?(delivery.image)
        }
        lock.lock()
        let more = !deliveries.isEmpty
        if !more { deliveryScheduled = false }
        lock.unlock()
        if more { DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) { [weak self] in self?.deliver() } }
    }

    private func persist(_ image: CGImage, key: String) {
        let bytes = image.bytesPerRow * image.height
        lock.lock()
        guard !pendingWriteKeys.contains(key), pendingWriteKeys.count < 8,
              pendingWriteBytes + bytes <= 32 * 1024 * 1024 else {
            measurements.skippedWrites += 1; lock.unlock(); return
        }
        pendingWriteKeys.insert(key); pendingWriteBytes += bytes
        lock.unlock()
        diskQueue.addOperation { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock(); self.pendingWriteKeys.remove(key); self.pendingWriteBytes -= bytes; self.lock.unlock()
            }
            autoreleasepool {
                try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
                let url = self.cacheURL(key)
                guard !FileManager.default.fileExists(atPath: url.path) else { return }
                let temporary = self.cacheDirectory.appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? FileManager.default.removeItem(at: temporary) }
                // PNG preserves transparency in normalized premultiplied bitmaps.
                let hasAlpha = self.hasTransparency(image)
                guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL,
                    (hasAlpha ? "public.png" : "public.jpeg") as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { return }
                do {
                    try FileManager.default.moveItem(at: temporary, to: url)
                    self.lock.lock(); self.measurements.diskWrites += 1; self.lock.unlock()
                } catch { /* A racing writer may already have stored this exact key. */ }
                self.trimDiskIfNeeded()
            }
        }
    }

    private func hasTransparency(_ image: CGImage) -> Bool {
        if [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) { return false }
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        for y in 0..<image.height {
            let row = bytes + y * image.bytesPerRow
            for x in 0..<image.width where row[x * 4 + 3] != 255 { return true }
        }
        return false
    }

    private func trimDiskIfNeeded() {
        guard Date().timeIntervalSince(lastTrim) > 120 else { return }
        lastTrim = Date()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: Array(keys))) ?? []
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard url.pathExtension == "thumb", let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > 512 * 1024 * 1024 else { return }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: url); total -= size
            if total < 384 * 1024 * 1024 { break }
        }
    }
}
