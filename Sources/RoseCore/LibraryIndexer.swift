import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ScanResult: Sendable {
    public let assets: [ImageAsset]
    public let directories: [String]
    public let isAvailable: Bool
    public let unreadableCount: Int
}

public enum LibraryIndexer {
    public static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "tif", "tiff", "bmp", "avif", "jxl"]

    public static func scan(root: VaultRoot, cached: [ImageAsset], observedAt: Date = Date(), progress: (@Sendable (Int) -> Void)? = nil,
                            batch: (@Sendable ([ImageAsset]) -> Void)? = nil) -> ScanResult {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              manager.isReadableFile(atPath: root.url.path) else {
            return ScanResult(assets: cached, directories: [], isAvailable: false, unreadableCount: 0)
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        var unreadable = 0
        guard let enumerator = manager.enumerator(at: root.url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in unreadable += 1; return true }) else {
            return ScanResult(assets: cached, directories: [], isAvailable: false, unreadableCount: 1)
        }
        let previous = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var assets: [ImageAsset] = []
        var directories: [String] = [root.url.path]
        for case let url as URL in enumerator {
            if Task<Never, Never>.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true { directories.append(url.path); continue }
            guard values.isRegularFile == true, supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let modification = values.contentModificationDate ?? .distantPast
            let size = Int64(values.fileSize ?? 0)
            let old = previous[url.path]
            // Fetch the optional directory timestamp only for new or unmigrated entries.
            let directoryAdded = old?.addedAt == nil
                ? (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate : nil
            let addedAt = AddedDate.resolve(recorded: old?.addedAt, directoryAdded: directoryAdded,
                created: values.creationDate, observedAt: observedAt,
                isExisting: old != nil || root.firstIndexedAt == nil)
            if var asset = previous[url.path], asset.modifiedAt == modification, asset.byteSize == size {
                asset.annotation = SidecarStore.read(for: url)
                asset.addedAt = addedAt
                assets.append(asset)
            } else {
                let asset: ImageAsset? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          CGImageSourceGetCount(source) > 0,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
                    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
                    let rotated = (5...8).contains(orientation)
                    return ImageAsset(url: url, rootID: root.id,
                        relativePath: String(url.path.dropFirst(root.url.path.count + 1)), byteSize: size,
                        modifiedAt: modification, createdAt: values.creationDate ?? modification,
                        width: rotated ? height : width, height: rotated ? width : height,
                        annotation: SidecarStore.read(for: url), addedAt: addedAt)
                }
                if let asset { assets.append(asset) } else { unreadable += 1 }
            }
            if assets.count.isMultiple(of: 100) { progress?(assets.count) }
            if assets.count.isMultiple(of: 200) { batch?(Array(assets.suffix(200))) }
        }
        return ScanResult(assets: assets, directories: directories, isAvailable: true, unreadableCount: unreadable)
    }

    public static func tree(root: VaultRoot, directories: [String], assets: [ImageAsset]) -> FolderNode {
        let directCounts = Dictionary(grouping: assets, by: \.folderPath).mapValues(\.count)
        var childPaths: [String: [String]] = [:]
        for path in Set(directories) where path != root.url.path {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            childPaths[parent, default: []].append(path)
        }
        func node(_ path: String) -> FolderNode {
            let children = (childPaths[path] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map(node)
            let count = directCounts[path, default: 0]
            return FolderNode(url: URL(fileURLWithPath: path), rootID: root.id, children: children,
                imageCount: count + children.reduce(0) { $0 + $1.imageCount }, directImageCount: count)
        }
        return node(root.url.path)
    }
}
