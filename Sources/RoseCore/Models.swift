import Foundation

public struct ImageAsset: Identifiable, Codable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let rootID: UUID
    public let relativePath: String
    public let byteSize: Int64
    public let modifiedAt: Date
    public let createdAt: Date
    // Optional so pre-feature JSON indexes remain readable. Scanning fills this once.
    public var addedAt: Date?
    public let width: Int
    public let height: Int
    public var annotation: ImageAnnotation

    public var name: String { url.lastPathComponent }
    public var folderPath: String { url.deletingLastPathComponent().path }
    public var fileExtension: String { url.pathExtension.lowercased() }
    public var dimensions: String { "\(width) × \(height)" }
    public var dateAdded: Date { addedAt ?? createdAt }
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    public init(url: URL, rootID: UUID, relativePath: String, byteSize: Int64,
                modifiedAt: Date, createdAt: Date, width: Int, height: Int,
                annotation: ImageAnnotation = .init(), addedAt: Date? = nil) {
        self.url = url; self.rootID = rootID; self.relativePath = relativePath
        self.byteSize = byteSize; self.modifiedAt = modifiedAt; self.createdAt = createdAt
        self.width = width; self.height = height; self.annotation = annotation
        self.addedAt = addedAt
    }
}

public struct ImageAnnotation: Codable, Hashable, Sendable {
    public var tags: [String]
    public var note: String
    public var isFavorite: Bool

    public init(tags: [String] = [], note: String = "", isFavorite: Bool = false) {
        self.tags = tags; self.note = note; self.isFavorite = isFavorite
    }
}

public struct VaultRoot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var url: URL
    public var bookmark: Data?
    public var isAvailable: Bool
    public var firstIndexedAt: Date?
    public var name: String { url.lastPathComponent }

    public init(id: UUID = UUID(), url: URL, bookmark: Data? = nil, isAvailable: Bool = true,
                firstIndexedAt: Date? = nil) {
        self.id = id; self.url = FileLocation.canonicalURL(url); self.bookmark = bookmark; self.isAvailable = isAvailable
        self.firstIndexedAt = firstIndexedAt
    }
}

public struct FolderNode: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let rootID: UUID
    public var children: [FolderNode]
    public var imageCount: Int
    public var directImageCount: Int
    public var name: String { url.lastPathComponent }

    public init(url: URL, rootID: UUID, children: [FolderNode] = [], imageCount: Int = 0, directImageCount: Int = 0) {
        self.url = url; self.rootID = rootID; self.children = children
        self.imageCount = imageCount; self.directImageCount = directImageCount
    }
}

public struct ImageCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var paths: Set<String>

    public init(id: UUID = UUID(), name: String, paths: Set<String> = []) {
        self.id = id; self.name = name; self.paths = paths
    }
}

public struct LibraryState: Codable, Sendable {
    public var roots: [VaultRoot] = []
    public var assets: [ImageAsset] = []
    public var recentPaths: [String] = []
    public var collections: [ImageCollection] = []
    public var folderPaths: [UUID: [String]] = [:]
    public init() {}
}

public enum LibraryLocation: Hashable, Sendable {
    case all, favorites, recent
    case folder(String)
    case tag(String)
    case collection(UUID)
}

public enum AssetSort: String, CaseIterable, Codable, Sendable {
    case name = "Name", added = "Date added", modified = "Date modified", created = "Date created", size = "File size", dimensions = "Dimensions"
}

public enum LibraryQuery {
    public static func filter(_ assets: [ImageAsset], location: LibraryLocation, search: String,
                              recursive: Bool, sort: AssetSort, ascending: Bool,
                              recentPaths: [String] = [], collections: [ImageCollection] = []) -> [ImageAsset] {
        let collectionPaths: Set<String>
        if case .collection(let id) = location { collectionPaths = collections.first { $0.id == id }?.paths ?? [] }
        else { collectionPaths = [] }
        let recentSet = Set(recentPaths)
        let terms = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var result = assets.filter { asset in
            let included: Bool
            switch location {
            case .all: included = true
            case .favorites: included = asset.annotation.isFavorite
            case .recent: included = recentSet.contains(asset.id)
            case .folder(let path):
                included = asset.folderPath == path || (recursive && asset.folderPath.hasPrefix(path + "/"))
            case .tag(let tag): included = asset.annotation.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            case .collection: included = collectionPaths.contains(asset.id)
            }
            guard included else { return false }
            let haystack = ([asset.name, asset.relativePath, asset.fileExtension] + asset.annotation.tags).joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        if location == .recent {
            let order = Dictionary(recentPaths.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
            result.sort { order[$0.id, default: .max] < order[$1.id, default: .max] }
        } else {
            result.sort { lhs, rhs in
                let order: ComparisonResult
                switch sort {
                case .name: order = lhs.name.localizedStandardCompare(rhs.name)
                case .added: order = compare(lhs.dateAdded, rhs.dateAdded)
                case .modified: order = compare(lhs.modifiedAt, rhs.modifiedAt)
                case .created: order = compare(lhs.createdAt, rhs.createdAt)
                case .size: order = compare(lhs.byteSize, rhs.byteSize)
                case .dimensions: order = compare(Int64(lhs.width) * Int64(lhs.height), Int64(rhs.width) * Int64(rhs.height))
                }
                if order == .orderedSame { return lhs.id < rhs.id }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        return result
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }
}
