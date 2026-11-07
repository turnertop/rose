import SwiftUI
import AppKit
import RoseCore
import UniformTypeIdentifiers

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var roots: [VaultRoot] = []
    @Published private(set) var assets: [ImageAsset] = []
    @Published private(set) var folders: [FolderNode] = []
    @Published private(set) var collections: [ImageCollection] = []
    @Published private(set) var recentPaths: [String] = []
    @Published private(set) var visibleAssets: [ImageAsset] = []
    @Published var location: LibraryLocation = .all { didSet { search = ""; rebuildVisible(); selection.removeAll(); primaryID = nil } }
    @Published var search = "" { didSet { rebuildVisible() } }
    @Published var recursive = true { didSet { rebuildVisible() } }
    @Published var sort: AssetSort {
        didSet {
            if sort == .added, sort != oldValue, ascending { ascending = false }
            else { saveSortPreference(); rebuildVisible() }
        }
    }
    @Published var ascending: Bool { didSet { saveSortPreference(); rebuildVisible() } }
    @Published var selection: Set<String> = []
    @Published var primaryID: String?
    @Published var thumbnailSize = ThumbnailSizePreference.load() {
        didSet { if thumbnailSize != oldValue { ThumbnailSizePreference.save(thumbnailSize) } }
    }
    @Published var displayMode = UserDefaults.standard.string(forKey: "rose.displayMode").flatMap(LibraryDisplayMode.init(rawValue:)) ?? .fill {
        didSet { if displayMode != oldValue { UserDefaults.standard.set(displayMode.rawValue, forKey: "rose.displayMode") } }
    }
    @Published var showSidebar = UserDefaults.standard.object(forKey: "rose.showSidebar") as? Bool ?? true {
        didSet { if showSidebar != oldValue { UserDefaults.standard.set(showSidebar, forKey: "rose.showSidebar") } }
    }
    @Published var showInspector = UserDefaults.standard.object(forKey: "rose.showInspector") as? Bool ?? true {
        didSet { if showInspector != oldValue { UserDefaults.standard.set(showInspector, forKey: "rose.showInspector") } }
    }
    @Published var viewerPresented = false
    @Published var isScanning = false
    @Published var scanCount = 0
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var expandedFolders: Set<String> = []
    @Published var collectionSheet = false

    private var directoryPaths: [UUID: [String]] = [:]
    private var watcher: DirectoryWatcher?
    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private let persistenceQueue = DispatchQueue(label: "app.rose.state", qos: .utility)
    private let annotationQueue = DispatchQueue(label: "app.rose.annotations", qos: .userInitiated)
    private var pendingAnnotations: [String: ImageAnnotation] = [:]
    private var draftNotes: [String: String] = [:]
    private var accessedURLs: [URL] = []
    private var generation = 0
    private var startupError = false
    private var dirtyRootIDs: Set<UUID> = []

    var selectedAsset: ImageAsset? { primaryID.flatMap { id in assets.first { $0.id == id } } }
    var allTags: [(name: String, count: Int)] {
        Dictionary(assets.flatMap { $0.annotation.tags }.map { ($0, 1) }, uniquingKeysWith: +)
            .map { (name: $0.key, count: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var favoriteCount: Int { assets.filter(\.annotation.isFavorite).count }
    var title: String {
        switch location {
        case .all: return "All images"
        case .favorites: return "Favorites"
        case .recent: return "Recently viewed"
        case .folder(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .tag(let tag): return tag
        case .collection(let id): return collections.first { $0.id == id }?.name ?? "Collection"
        }
    }
    var breadcrumb: String {
        if case .folder(let path) = location,
           let root = roots.first(where: { path == $0.url.path || path.hasPrefix($0.url.path + "/") }) {
            let relative = path == root.url.path ? root.name : root.name + " / " + String(path.dropFirst(root.url.path.count + 1)).replacingOccurrences(of: "/", with: " / ")
            return relative
        }
        return "Your image library"
    }
    var selectedFolderUnavailable: Bool {
        if case .folder(let path) = location {
            return roots.contains { !$0.isAvailable && (path == $0.url.path || path.hasPrefix($0.url.path + "/")) }
                || !FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    init() {
        let savedSort = SortPreference.load(validFields: AssetSort.allCases.map(\.rawValue))
        sort = savedSort.flatMap { AssetSort(rawValue: $0.field) } ?? .name
        // Initialize directly so restoring an oldest-first Date added choice
        // does not invoke the interactive newest-first selection behavior.
        ascending = savedSort?.ascending ?? true
        do {
            let state = try StateStore.load()
            roots = state.roots; assets = state.assets; collections = state.collections
            recentPaths = state.recentPaths; directoryPaths = state.folderPaths
        } catch {
            startupError = true
            errorMessage = "Rose couldn’t read its saved library. The existing library file has been kept. \(error.localizedDescription)"
        }
        for index in roots.indices {
            if let bookmark = roots[index].bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    roots[index].url = FileLocation.canonicalURL(url)
                    if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
                    if stale { roots[index].bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
                }
            }
            roots[index].isAvailable = FileManager.default.isReadableFile(atPath: roots[index].url.path)
            expandedFolders.insert(roots[index].url.path)
        }
        rebuildFolders(); rebuildVisible(); installWatcher()
        if !roots.isEmpty { refresh() }
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--vault"), arguments.indices.contains(i + 1) {
            connect([URL(fileURLWithPath: arguments[i + 1], isDirectory: true)])
        }
    }

    private func saveSortPreference() {
        SortPreference.save(field: sort.rawValue, ascending: ascending)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open a folder in Rose"
        panel.message = "Your images stay exactly where they are. Rose remembers this folder and follows its changes."
        panel.prompt = "Open folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.connect(panel.urls) }
        }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
    }

    func toggleInspector() {
        withAnimation(.easeInOut(duration: 0.18)) { showInspector.toggle() }
    }

    func connect(_ urls: [URL]) {
        var target: URL?
        for raw in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: raw.path, isDirectory: &isDirectory) else { continue }
            let url = FileLocation.canonicalURL(isDirectory.boolValue ? raw : raw.deletingLastPathComponent())
            target = url
            if let existing = roots.first(where: { url.path == $0.url.path || url.path.hasPrefix($0.url.path + "/") }) {
                if !existing.isAvailable { refresh(rootIDs: [existing.id]) }
                continue
            }
            if roots.contains(where: { $0.url.path.hasPrefix(url.path + "/") }) {
                errorMessage = "A subfolder of “\(url.lastPathComponent)” is already connected. Remove that connection first, then open this parent folder. Your files will stay in place."
                continue
            }
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let root = VaultRoot(url: url, bookmark: bookmark)
            roots.append(root)
            directoryPaths[root.id] = [url.path]
            expandedFolders.insert(url.path)
            dirtyRootIDs.insert(root.id)
        }
        if let target { location = .folder(target.path) }
        rebuildFolders(); installWatcher(); persistSoon(); refresh()
    }

    func removeRoot(_ root: VaultRoot) {
        roots.removeAll { $0.id == root.id }; assets.removeAll { $0.rootID == root.id }
        directoryPaths.removeValue(forKey: root.id)
        if case .folder(let path) = location, path == root.url.path || path.hasPrefix(root.url.path + "/") { location = .all }
        rebuildFolders(); rebuildVisible(); installWatcher(); persistSoon()
    }

    func refresh(rootIDs: Set<UUID>? = nil) {
        if let rootIDs { dirtyRootIDs.formUnion(rootIDs) }
        else { dirtyRootIDs.formUnion(roots.map(\.id)) }
        guard !isScanning else { return }
        let ids = dirtyRootIDs
        dirtyRootIDs.removeAll()
        let scanRoots = roots.filter { ids.contains($0.id) }
        guard !scanRoots.isEmpty else { return }
        generation += 1
        let currentGeneration = generation
        let cached = assets
        isScanning = true; scanCount = 0
        scanTask = Task { [weak self] in
            guard let self else { return }
            for root in scanRoots {
                guard !Task.isCancelled else { break }
                let rootAssets = cached.filter { $0.rootID == root.id }
                let result = await Task.detached(priority: .userInitiated) {
                    LibraryIndexer.scan(root: root, cached: rootAssets, progress: { count in
                        Task { @MainActor in if self.generation == currentGeneration { self.scanCount = count } }
                    }, batch: { batch in
                        Task { @MainActor in
                            guard self.generation == currentGeneration, self.isScanning,
                                  self.roots.contains(where: { $0.id == root.id }) else { return }
                            let positions = Dictionary(self.assets.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
                            for var asset in batch {
                                if let annotation = self.pendingAnnotations[asset.id] { asset.annotation = annotation }
                                if let index = positions[asset.id] { self.assets[index] = asset }
                                else { self.assets.append(asset) }
                            }
                            self.rebuildVisible()
                        }
                    })
                }.value
                guard !Task.isCancelled, self.generation == currentGeneration,
                      let index = self.roots.firstIndex(where: { $0.id == root.id }) else { continue }
                self.roots[index].isAvailable = result.isAvailable
                let next = result.assets.map { asset -> ImageAsset in
                    var updated = asset
                    if let annotation = self.pendingAnnotations[asset.id] { updated.annotation = annotation }
                    return updated
                }
                self.assets.removeAll { $0.rootID == root.id }
                self.assets.append(contentsOf: next)
                if result.isAvailable {
                    self.directoryPaths[root.id] = result.directories
                    if self.roots[index].firstIndexedAt == nil { self.roots[index].firstIndexedAt = Date() }
                }
                self.rebuildFolders(); self.rebuildVisible()
                if result.unreadableCount > 0 { self.statusMessage = "\(result.unreadableCount) unreadable or unsupported file\(result.unreadableCount == 1 ? "" : "s") skipped" }
            }
            self.isScanning = false; self.persistSoon()
            if !self.dirtyRootIDs.isEmpty { self.refresh(rootIDs: []) }
        }
    }

    func select(_ ids: Set<String>, primary: String?) {
        selection = ids
        primaryID = primary.flatMap { ids.contains($0) ? $0 : nil } ?? visibleAssets.first { ids.contains($0.id) }?.id
        if let id = primaryID {
            recentPaths.removeAll { $0 == id }; recentPaths.insert(id, at: 0)
            recentPaths = Array(recentPaths.prefix(200))
            persistSoon()
        }
    }

    func navigate(_ delta: Int) {
        guard !visibleAssets.isEmpty else { return }
        let index = primaryID.flatMap { id in visibleAssets.firstIndex { $0.id == id } } ?? (delta > 0 ? -1 : visibleAssets.count)
        let next = max(0, min(visibleAssets.count - 1, index + delta))
        let id = visibleAssets[next].id
        select([id], primary: id)
    }

    func selectAll() { select(Set(visibleAssets.map(\.id)), primary: primaryID ?? visibleAssets.first?.id) }

    func updateAnnotation(id: String, _ change: (inout ImageAnnotation) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        var annotation = assets[index].annotation
        change(&annotation)
        guard annotation != assets[index].annotation else { return }
        let old = assets[index].annotation
        let url = assets[index].url
        assets[index].annotation = annotation
        pendingAnnotations[id] = annotation
        rebuildVisible(); persistSoon()
        let savedAnnotation = annotation
        annotationQueue.async { [self] in
            do {
                try SidecarStore.write(savedAnnotation, for: url)
                Task { @MainActor in
                    if self.pendingAnnotations[id] == savedAnnotation { self.pendingAnnotations.removeValue(forKey: id) }
                }
            } catch {
                Task { @MainActor in
                    if self.pendingAnnotations[id] == savedAnnotation {
                        self.pendingAnnotations.removeValue(forKey: id)
                        if let index = self.assets.firstIndex(where: { $0.id == id }) { self.assets[index].annotation = old }
                        self.rebuildVisible()
                    }
                    self.errorMessage = "The note beside “\(url.lastPathComponent)” couldn’t be saved. \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleFavorite(_ asset: ImageAsset? = nil) {
        guard let asset = asset ?? selectedAsset else { return }
        updateAnnotation(id: asset.id) { $0.isFavorite.toggle() }
    }

    func stageNote(id: String, note: String) { draftNotes[id] = note }

    func saveNote(id: String, note: String) {
        draftNotes.removeValue(forKey: id)
        updateAnnotation(id: id) { $0.note = note }
    }

    func createCollection(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collection = ImageCollection(name: name, paths: selection)
        collections.append(collection); location = .collection(collection.id); persistSoon()
    }

    func addToCollection(_ id: UUID, paths: Set<String>) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].paths.formUnion(paths); rebuildVisible(); persistSoon()
    }

    func removeCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        if location == .collection(id) { location = .all }
        persistSoon()
    }

    func removeFromCollection(paths: Set<String>) {
        guard case .collection(let id) = location, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].paths.subtract(paths); rebuildVisible(); persistSoon()
    }

    func reveal(_ asset: ImageAsset? = nil) {
        guard let asset = asset ?? selectedAsset else { return }
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
    }

    func copyPath(_ asset: ImageAsset? = nil) {
        guard let asset = asset ?? selectedAsset else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(asset.id, forType: .string)
    }

    func copyImage(_ asset: ImageAsset? = nil) {
        guard let asset = asset ?? selectedAsset else { return }
        let url = asset.url
        Task.detached(priority: .userInitiated) {
            guard let data = NSImage(contentsOf: url)?.tiffRepresentation else { return }
            await MainActor.run { NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .tiff) }
        }
    }

    func trash(_ asset: ImageAsset? = nil) {
        guard let asset = asset ?? selectedAsset else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(asset.name)” to the Trash?"
        alert.informativeText = "The original image and its Markdown sidecar will be moved to the Trash. You can restore them in Finder."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            let sidecar = SidecarStore.url(for: asset.url)
            if FileManager.default.fileExists(atPath: sidecar.path) { try FileManager.default.trashItem(at: sidecar, resultingItemURL: nil) }
            assets.removeAll { $0.id == asset.id }; selection.remove(asset.id)
            if primaryID == asset.id { primaryID = nil }
            rebuildVisible(); rebuildFolders(); persistSoon()
        } catch { errorMessage = "The file couldn’t be moved to the Trash. \(error.localizedDescription)" }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let dropped = DroppedURLs()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                if let url { dropped.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.connect(dropped.values) }
        return true
    }

    func flush() {
        let drafts = draftNotes
        for (id, note) in drafts { saveNote(id: id, note: note) }
        persistenceTask?.cancel()
        guard !startupError else { return }
        let state = snapshot()
        persistenceQueue.sync { try? StateStore.save(state) }
        annotationQueue.sync {}
    }

    private func rebuildVisible() {
        visibleAssets = LibraryQuery.filter(assets, location: location, search: search, recursive: recursive,
            sort: sort, ascending: ascending, recentPaths: recentPaths, collections: collections)
        let visibleIDs = Set(visibleAssets.map(\.id))
        selection.formIntersection(visibleIDs)
        if let primaryID, !visibleIDs.contains(primaryID) { self.primaryID = visibleAssets.first { selection.contains($0.id) }?.id }
    }

    private func rebuildFolders() {
        folders = roots.map { root in
            LibraryIndexer.tree(root: root, directories: directoryPaths[root.id] ?? [root.url.path], assets: assets.filter { $0.rootID == root.id })
        }
    }

    private func installWatcher() {
        watcher = DirectoryWatcher(urls: roots.map(\.url)) { [weak self] paths in
            guard let self else { return }
            let ids = Set(self.roots.filter { root in paths.contains { $0 == root.url.path || $0.hasPrefix(root.url.path + "/") || root.url.path.hasPrefix($0 + "/") } }.map(\.id))
            self.dirtyRootIDs.formUnion(ids)
            self.refreshTask?.cancel()
            self.refreshTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                self?.refresh(rootIDs: [])
            }
        }
    }

    private func snapshot() -> LibraryState {
        var state = LibraryState()
        state.roots = roots; state.assets = assets; state.recentPaths = recentPaths
        state.collections = collections; state.folderPaths = directoryPaths
        return state
    }

    private func persistSoon() {
        guard !startupError else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let state = self.snapshot()
            self.persistenceQueue.async { [self] in
                do { try StateStore.save(state) }
                catch { Task { @MainActor in self.errorMessage = "Rose couldn’t save the library index. \(error.localizedDescription)" } }
            }
        }
    }
}

private final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; urls.append(url) }
    var values: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}
