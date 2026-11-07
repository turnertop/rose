import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import RoseCore
import RoseImaging

enum CheckFailure: Error { case failed(String), timeout }

@MainActor
final class ImageWaiter {
    var continuation: CheckedContinuation<CGImage?, Error>?
    var token: ThumbnailRequest?
    init(_ continuation: CheckedContinuation<CGImage?, Error>) { self.continuation = continuation }
    func finish(_ result: Result<CGImage?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        if case .failure = result { token?.cancel() }
        continuation.resume(with: result)
    }
}

@MainActor
func image(_ service: ThumbnailService, _ asset: ImageAsset, pixels: Int = 320) async throws -> CGImage? {
    try await withCheckedThrowingContinuation { continuation in
        let waiter = ImageWaiter(continuation)
        waiter.token = service.load(asset, maxPixel: pixels) { result in waiter.finish(.success(result)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { waiter.finish(.failure(CheckFailure.timeout)) }
    }
}

func writeFixture(_ url: URL, alpha: Bool = false, orientation: Int = 1, green: Bool = false, wideGamut: Bool = false) throws {
    let colorSpace = CGColorSpace(name: wideGamut ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: green ? 0 : 0.9, green: green ? 0.9 : 0.1, blue: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: alpha ? 600 : 1200, height: 800))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, (url.pathExtension == "png" ? "public.png" : "public.jpeg") as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CheckFailure.failed("write fixture") }
}

func cacheKey(_ asset: ImageAsset, pixels: Int) -> String {
    let key = "v2|\(asset.id)|\(asset.modifiedAt.timeIntervalSince1970)|\(asset.byteSize)|\(pixels)"
    return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".thumb"
}

func drained(_ queue: OperationQueue) async {
    await withCheckedContinuation { continuation in queue.addBarrierBlock { continuation.resume() } }
}

@main
struct ImagingChecks {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }

    @MainActor static func run() async throws {
        var count = 0
        func check(_ message: String, _ value: Bool) throws {
            guard value else { throw CheckFailure.failed(message) }
            count += 1; print("✓ \(message)")
        }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("rose-image-checks-\(UUID().uuidString)", isDirectory: true)
        let source = base.appendingPathComponent("Images", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try writeFixture(source.appendingPathComponent("Opaque.jpg"))
        try writeFixture(source.appendingPathComponent("Alpha.png"), alpha: true)
        try writeFixture(source.appendingPathComponent("Rotated.jpg"), orientation: 6)
        try writeFixture(source.appendingPathComponent("Wide.png"), wideGamut: true)
        for index in 0..<32 { try fm.linkItem(at: source.appendingPathComponent("Opaque.jpg"), to: source.appendingPathComponent("Burst \(index).jpg")) }
        let root = VaultRoot(url: source)
        let assets = LibraryIndexer.scan(root: root, cached: []).assets
        let opaque = assets.first { $0.name == "Opaque.jpg" }!
        let alpha = assets.first { $0.name == "Alpha.png" }!
        let rotated = assets.first { $0.name == "Rotated.jpg" }!
        let wide = assets.first { $0.name == "Wide.png" }!
        let burst = assets.filter { $0.name.hasPrefix("Burst ") }
        let originalBytes = try Data(contentsOf: opaque.url)

        let writes = OperationQueue(); writes.isSuspended = true
        let cache = base.appendingPathComponent("Cache", isDirectory: true)
        let service = ThumbnailService(cacheDirectory: cache, diskQueue: writes)
        let first = try await image(service, opaque)!
        try check("Source images are downsampled to the requested pixel limit", first.width == 320 && abs(first.height - 213) <= 1)
        try check("Thumbnails arrive as normalized, decoded 32-bit sRGB bitmaps", first.bitsPerPixel == 32 && first.bitsPerComponent == 8 && first.colorSpace?.name == CGColorSpace.sRGB)
        try check("Visible results do not wait for a suspended disk writer", service.metrics().sourceDecodes == 1 && service.metrics().diskWrites == 0)
        try check("The cache is not written synchronously by a decoder", !fm.fileExists(atPath: cache.path))
        writes.isSuspended = false
        await service.waitForCacheWrites()
        try check("Cache writes finish independently after delivery", service.metrics().diskWrites == 1)
        _ = try await image(service, opaque)
        try check("A second request uses the decoded memory cache", service.metrics().memoryHits == 1 && service.metrics().sourceDecodes == 1)
        service.clearMemory()
        let disk = try await image(service, opaque)!
        try check("A cold memory cache reads the existing disk thumbnail", service.metrics().diskHits == 1 && service.metrics().sourceDecodes == 1 && disk.width == 320)
        let fresh = ThumbnailService(cacheDirectory: cache)
        _ = try await image(fresh, opaque, pixels: 160)
        try check("A larger existing thumbnail seeds smaller display sizes", fresh.metrics().diskHits == 1 && fresh.metrics().sourceDecodes == 0)

        let legacyCache = base.appendingPathComponent("Legacy")
        try fm.createDirectory(at: legacyCache, withIntermediateDirectories: true)
        let legacyDestination = CGImageDestinationCreateWithURL(legacyCache.appendingPathComponent(cacheKey(opaque, pixels: 640)) as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(legacyDestination, first, nil)
        guard CGImageDestinationFinalize(legacyDestination) else { throw CheckFailure.failed("write legacy cache") }
        let legacy = ThumbnailService(cacheDirectory: legacyCache)
        let legacyImage = try await image(legacy, opaque, pixels: 640)
        try check("Existing v2 disk-cache entries survive the upgrade", legacyImage != nil && legacy.metrics().diskHits == 1 && legacy.metrics().sourceDecodes == 0)
        let mainThreadDelivery = await withCheckedContinuation { continuation in
            service.load(opaque, maxPixel: 320) { _ in continuation.resume(returning: Thread.isMainThread) }
        }
        try check("Image callbacks are delivered on the UI thread", mainThreadDelivery)

        let alphaImage = try await image(service, alpha)!
        let alphaData = alphaImage.dataProvider!.data!
        let alphaBytes = CFDataGetBytePtr(alphaData)!
        let middle = (alphaImage.height / 2) * alphaImage.bytesPerRow
        try check("Bitmap preparation preserves transparent pixels", alphaBytes[middle + 3] == 255 && alphaBytes[middle + (alphaImage.width - 1) * 4 + 3] == 0)
        await service.waitForCacheWrites()
        service.clearMemory()
        let alphaDisk = try await image(service, alpha)!
        let diskAlphaData = alphaDisk.dataProvider!.data!
        let diskAlphaBytes = CFDataGetBytePtr(diskAlphaData)!
        try check("Transparency survives a disk-cache round trip", diskAlphaBytes[(alphaDisk.height / 2) * alphaDisk.bytesPerRow + (alphaDisk.width - 1) * 4 + 3] == 0)
        let portrait = try await image(service, rotated)!
        try check("EXIF rotation remains correct after background preparation", portrait.height == 320 && portrait.width < portrait.height)
        let wideImage = try await image(service, wide)!
        try check("Background preparation preserves Display P3 color profiles", wideImage.colorSpace?.name == CGColorSpace.displayP3)
        let offline = source.appendingPathComponent("Opaque.offline")
        try fm.moveItem(at: opaque.url, to: offline)
        let missing = try await image(service, opaque)
        try check("Warm thumbnails never substitute for a missing source", missing == nil)
        try fm.moveItem(at: offline, to: opaque.url)
        try check("Loading and caching never change original image bytes", try Data(contentsOf: opaque.url) == originalBytes)

        let lookup = OperationQueue(); lookup.isSuspended = true
        let deduplicated = ThumbnailService(cacheDirectory: base.appendingPathComponent("Deduplicated"), lookupQueue: lookup)
        var unwantedDelivery = false
        let cancelled = deduplicated.load(opaque, maxPixel: 320, priority: .prefetch) { _ in unwantedDelivery = true }
        let survivor = Task { @MainActor in try await image(deduplicated, opaque) }
        while deduplicated.metrics().requests < 2 { await Task.yield() }
        try check("Overlapping requests share one in-flight job", deduplicated.metrics().coalesced == 1 && deduplicated.metrics().pendingJobs == 1)
        try check("An arriving visible request promotes a prefetch operation", lookup.operations.first?.queuePriority == .high)
        cancelled.cancel(); lookup.isSuspended = false
        let survivingImage = try await survivor.value
        try check("Cancelling one subscriber keeps the other request alive", survivingImage != nil && !unwantedDelivery && deduplicated.metrics().sourceDecodes == 1)

        let blockedLookup = OperationQueue(); blockedLookup.isSuspended = true
        let churn = ThumbnailService(cacheDirectory: base.appendingPathComponent("Churn"), lookupQueue: blockedLookup)
        var obsoleteDelivery = false
        for _ in 0..<8 {
            let requests = burst.map { churn.load($0, maxPixel: 320, priority: .prefetch) { _ in obsoleteDelivery = true } }
            requests.forEach { $0.cancel() }
        }
        try check("Skipped scroll positions retire their queued jobs", churn.metrics().pendingJobs == 0 && churn.metrics().cancelled == 256)
        blockedLookup.isSuspended = false
        await drained(blockedLookup)
        try check("Cancelled rows do not decode or update recycled cells", churn.metrics().sourceDecodes == 0 && !obsoleteDelivery)

        let decode = OperationQueue()
        let fastLookup = OperationQueue()
        let fast = ThumbnailService(cacheDirectory: base.appendingPathComponent("Fast"), lookupQueue: fastLookup, decodeQueue: decode)
        _ = try await image(fast, opaque)
        decode.isSuspended = true
        let blocked = burst.prefix(3).map { fast.load($0, maxPixel: 320) }
        await drained(fastLookup)
        let cacheStart = ProcessInfo.processInfo.systemUptime
        let warm = try await image(fast, opaque)
        let warmMilliseconds = (ProcessInfo.processInfo.systemUptime - cacheStart) * 1000
        try check("A memory hit bypasses a blocked source-decode queue", warm != nil && fast.metrics().memoryHits == 1 && fast.metrics().sourceDecodes == 1)
        blocked.forEach { $0.cancel() }; decode.isSuspended = false
        let clientA = UUID(), clientB = UUID()
        fast.setRapidScrolling(true, client: clientA); fast.setRapidScrolling(true, client: clientB)
        fast.setRapidScrolling(false, client: clientA)
        try check("Rapid scrolling limits source decoding while any window is flinging", decode.maxConcurrentOperationCount == 1)
        fast.setRapidScrolling(false, client: clientB)
        try check("Source concurrency recovers after all scrolls settle", decode.maxConcurrentOperationCount == 2)

        let delayedWrites = OperationQueue(); delayedWrites.isSuspended = true
        let bounded = ThumbnailService(cacheDirectory: base.appendingPathComponent("Bounded"), diskQueue: delayedWrites)
        for asset in burst.prefix(16) { _ = try await image(bounded, asset) }
        try check("A slow writer cannot retain an unbounded bitmap backlog", delayedWrites.operationCount <= 8 && bounded.metrics().skippedWrites >= 8)
        delayedWrites.isSuspended = false
        await bounded.waitForCacheWrites()
        try check("Only complete, atomically published cache files remain", try fm.contentsOfDirectory(atPath: base.appendingPathComponent("Bounded").path).allSatisfy { $0.hasSuffix(".thumb") })

        let repairDirectory = base.appendingPathComponent("Repair")
        try fm.createDirectory(at: repairDirectory, withIntermediateDirectories: true)
        try Data("damaged cache".utf8).write(to: repairDirectory.appendingPathComponent(cacheKey(opaque, pixels: 320)))
        let repair = ThumbnailService(cacheDirectory: repairDirectory)
        _ = try await image(repair, opaque)
        await repair.waitForCacheWrites()
        repair.clearMemory(); _ = try await image(repair, opaque)
        try check("A corrupt disk thumbnail is regenerated and reusable", repair.metrics().sourceDecodes == 1 && repair.metrics().diskHits == 1)
        try writeFixture(opaque.url, green: true)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: opaque.id)
        let changed = LibraryIndexer.scan(root: root, cached: []).assets.first { $0.id == opaque.id }!
        _ = try await image(repair, changed)
        try check("Changed originals invalidate the old thumbnail key", repair.metrics().sourceDecodes == 2)

        let group = ThumbnailService(cacheDirectory: base.appendingPathComponent("Delivery"))
        let images = try await withThrowingTaskGroup(of: Bool.self) { tasks in
            for asset in burst.prefix(16) { tasks.addTask { try await image(group, asset) != nil } }
            var loaded = 0
            for try await result in tasks { if result { loaded += 1 } }
            return loaded
        }
        try check("Burst results all arrive through the bounded delivery pump", images == 16 && group.metrics().maxDeliveryBatch <= 4)
        try check("Retina thumbnail sizing uses stable bounded resolutions", ThumbnailSize.pixels(width: 56, height: 56, scale: 2) == 160 && ThumbnailSize.pixels(width: 190, height: 213, scale: 2) == 640 && ThumbnailSize.pixels(width: 5000, height: 100, scale: 2) == 1600)

        for instance in [service, fresh, legacy, deduplicated, churn, fast, bounded, repair, group] {
            await instance.waitForCacheWrites()
        }
        print(String(format: "Memory hit with source decoders suspended: %.2f ms (headless pipeline timing, not UI frame rate).", warmMilliseconds))
        print("\n\(count) image-pipeline checks passed.")
    }
}
