import Foundation
import ImageIO
import CoreGraphics
import RoseCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case .failed(let name) = self { return name }; return "" }
}

var passed = 0
func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
    guard try condition() else { throw CheckFailure.failed(name) }
    passed += 1
    print("✓ \(name)")
}

func writePNG(_ url: URL, width: Int = 40, height: Int = 30) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.95, green: 0.32, blue: 0.57, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CheckFailure.failed("Create fixture image") }
}

func runChecks() throws {
    let fm = FileManager.default
    let base = FileLocation.canonicalURL(fm.temporaryDirectory).appendingPathComponent("rose-checks-\(UUID().uuidString)", isDirectory: true)
    let rootURL = base.appendingPathComponent("References", isDirectory: true)
    let nested = rootURL.appendingPathComponent("Botanical", isDirectory: true)
    let sibling = rootURL.appendingPathComponent("Botanical-extra", isDirectory: true)
    let empty = nested.appendingPathComponent("Empty", isDirectory: true)
    for url in [rootURL, nested, sibling, empty] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: base) }

    let image2 = rootURL.appendingPathComponent("Image 2.png")
    let image10 = nested.appendingPathComponent("Image 10.png")
    let other = sibling.appendingPathComponent("Other.png")
    try writePNG(image2); try writePNG(image10, width: 80, height: 60); try writePNG(other)
    try Data("Not a real image".utf8).write(to: rootURL.appendingPathComponent("broken.jpg"))
    try Data("A non-image".utf8).write(to: rootURL.appendingPathComponent("Readme.txt"))
    try fm.createSymbolicLink(at: rootURL.appendingPathComponent("loop"), withDestinationURL: rootURL)
    let originalBytes = try Data(contentsOf: image2)
    let root = VaultRoot(url: rootURL)
    var scan = LibraryIndexer.scan(root: root, cached: [])
    try check("Finds images in connected folders and nested folders", scan.assets.count == 3)
    try check("Skips corrupt images without dropping valid ones", scan.unreadableCount == 1)
    try check("Reads pixel dimensions using ImageIO", scan.assets.first { $0.url == image10 }?.width == 80)
    try check("Keeps empty folders in the navigation tree", scan.directories.contains(empty.path))
    try check("Does not follow symlink loops", !scan.directories.contains(rootURL.appendingPathComponent("loop").path))

    let tree = LibraryIndexer.tree(root: root, directories: scan.directories, assets: scan.assets)
    try check("Tree rolls up descendant image counts", tree.imageCount == 3 && tree.directImageCount == 1)
    try check("Nested tree counts stay accurate", tree.children.first { $0.name == "Botanical" }?.imageCount == 1)
    try check("Empty descendants stay in the tree", tree.children.first { $0.name == "Botanical" }?.children.first?.imageCount == 0)

    func query(_ location: LibraryLocation = .all, recursive: Bool = true, search: String = "", sort: AssetSort = .name, ascending: Bool = true,
               recent: [String] = [], collections: [ImageCollection] = []) -> [ImageAsset] {
        LibraryQuery.filter(scan.assets, location: location, search: search, recursive: recursive, sort: sort,
            ascending: ascending, recentPaths: recent, collections: collections)
    }
    try check("Direct folder view excludes descendants", query(.folder(rootURL.path), recursive: false).count == 1)
    try check("Recursive folder view includes descendants", query(.folder(rootURL.path)).count == 3)
    try check("Folder matching respects path boundaries", query(.folder(nested.path)).map(\.url) == [image10])
    try check("Natural filename sort orders 2 before 10", query().prefix(2).map(\.name) == ["Image 2.png", "Image 10.png"])
    try check("Dimensions sort uses pixel area", query(sort: .dimensions, ascending: false).first?.url == image10)
    try check("Search combines terms across filename and folder", query(search: "botanical 10 png").map(\.url) == [image10])
    try check("Search does not invent results", query(search: "nonexistent").isEmpty)
    let recent = [other.path, image2.path]
    try check("Recent images preserve viewing order", query(.recent, recent: recent).map(\.id) == recent)
    let collection = ImageCollection(name: "Moodboard", paths: [image2.path, image10.path])
    try check("Collections reference original file paths", Set(query(.collection(collection.id), collections: [collection]).map(\.id)) == collection.paths)

    let annotation = ImageAnnotation(tags: ["rose quartz", "日本語", "a: b", "quote \" and slash \\"],
        note: "## Reference\n\n- A **pink** palette\n- [A link](https://example.com)\n", isFavorite: true)
    try SidecarStore.write(annotation, for: image2)
    try check("Markdown annotations round-trip Unicode and punctuation", SidecarStore.read(for: image2) == annotation)
    try check("Annotations never modify original image bytes", try Data(contentsOf: image2) == originalBytes)
    try check("Sidecars keep the full extension to avoid collisions", SidecarStore.url(for: image2).lastPathComponent == "Image 2.png.md")
    try check("Ordinary Markdown notes work without frontmatter", SidecarStore.decode("# My note\n").note == "# My note\n")
    try check("Empty frontmatter does not crash or swallow notes", SidecarStore.decode("---\n---\nhello").note == "hello")
    try check("Unterminated frontmatter is preserved as note text", SidecarStore.decode("---\ntags: [test]").note == "---\ntags: [test]")
    let preserved = SidecarStore.encode(annotation, preserving: "---\nauthor: Jane Doe\ncustom: keep me\nfavorite: false\n---\nOld note")
    try check("Unknown frontmatter fields survive updates", preserved.contains("author: Jane Doe") && preserved.contains("custom: keep me"))
    try check("Markdown body survives encoding exactly", SidecarStore.decode(preserved).note == annotation.note)
    let yamlTags = "---\ntags:\n  - botanical\n  - 'rose quartz'\n  - \"日本語\"\nauthor: Jane Doe\n---\nA note"
    try check("Reads common YAML list tags in existing Markdown", SidecarStore.decode(yamlTags).tags == ["botanical", "rose quartz", "日本語"])
    let replacedTags = SidecarStore.encode(annotation, preserving: yamlTags)
    try check("Updating YAML list tags leaves no orphaned list items", !replacedTags.contains("  - botanical") && replacedTags.contains("author: Jane Doe"))

    scan = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("Cached metadata still refreshes changed sidecars", scan.assets.first { $0.url == image2 }?.annotation == annotation)
    try check("Favorites filter uses portable sidecar metadata", query(.favorites).map(\.url) == [image2])
    try check("Tag search works without renaming images", query(search: "日本語").map(\.url) == [image2])
    try check("Tag navigation ignores case", query(.tag("ROSE QUARTZ")).map(\.url) == [image2])

    try writePNG(image10, width: 91, height: 47)
    scan = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("Changed files invalidate cached dimensions", scan.assets.first { $0.url == image10 }?.dimensions == "91 × 47")
    let added = nested.appendingPathComponent("New.png")
    try writePNG(added)
    scan = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("An external addition appears on the next scan", scan.assets.contains { $0.url == added })
    let renamed = nested.appendingPathComponent("Renamed.png")
    try fm.moveItem(at: added, to: renamed)
    scan = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("External renames remove stale paths", scan.assets.contains { $0.url == renamed } && !scan.assets.contains { $0.url == added })
    try fm.removeItem(at: renamed)
    scan = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("External deletion removes stale entries", !scan.assets.contains { $0.url == renamed })

    var state = LibraryState()
    state.roots = [root]; state.assets = scan.assets; state.recentPaths = recent; state.collections = [collection]
    state.folderPaths = [root.id: scan.directories]
    let stateDirectory = base.appendingPathComponent("State", isDirectory: true)
    try StateStore.save(state, to: stateDirectory)
    let reloaded = try StateStore.load(from: stateDirectory)
    try check("Connected folders survive an app restart", reloaded.roots == [root])
    try check("The warm index survives an app restart", reloaded.assets == scan.assets)
    try check("Collections and recents survive an app restart", reloaded.collections == [collection] && reloaded.recentPaths == recent)
    try check("Nested navigation survives an app restart", reloaded.folderPaths[root.id] == scan.directories)
    let offlineURL = base.appendingPathComponent("Offline")
    try fm.moveItem(at: rootURL, to: offlineURL)
    let offline = LibraryIndexer.scan(root: root, cached: scan.assets)
    try check("Unavailable roots retain their saved index", !offline.isAvailable && offline.assets == scan.assets)
    try check("A missing state file starts with a clean library", try StateStore.load(from: base.appendingPathComponent("NewState")).roots.isEmpty)
    try Data("invalid json".utf8).write(to: stateDirectory.appendingPathComponent("library.json"))
    var detectedCorruption = false
    do { _ = try StateStore.load(from: stateDirectory) } catch { detectedCorruption = true }
    try check("Corrupt state is reported rather than silently replaced", detectedCorruption)

    if CommandLine.arguments.contains("--benchmark") {
        let benchmarkURL = base.appendingPathComponent("Large library", isDirectory: true)
        try fm.createDirectory(at: benchmarkURL, withIntermediateDirectories: true)
        let seed = benchmarkURL.appendingPathComponent("Reference 0.png")
        try writePNG(seed)
        for i in 1..<3000 { try fm.linkItem(at: seed, to: benchmarkURL.appendingPathComponent("Reference \(i).png")) }
        let benchmarkRoot = VaultRoot(url: benchmarkURL)
        let start = Date()
        let initial = LibraryIndexer.scan(root: benchmarkRoot, cached: [])
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        let warm = LibraryIndexer.scan(root: benchmarkRoot, cached: initial.assets)
        let warmTime = Date().timeIntervalSince(warmStart)
        try check("Indexes 3,000 images and reuses their metadata", initial.assets.count == 3000 && warm.assets.count == 3000)
        print(String(format: "3,000 small fixture images: cold %.3fs, warm %.3fs (filesystem/index check; not a scrolling benchmark).", cold, warmTime))
    }
}

do {
    try runChecks()
    try runAddedDateChecks()
    try runJustifiedLayoutChecks()
    print("\n\(passed) checks passed.")
} catch {
    fputs("\nFAIL: \(error)\n", stderr)
    exit(1)
}
