import Foundation
import RoseCore

func runAddedDateChecks() throws {
    let old = Date(timeIntervalSince1970: 1_600_000_000)
    let arrival = old.addingTimeInterval(100)
    let observation = old.addingTimeInterval(200)
    try check("Directory arrival wins over an inherited creation date",
        AddedDate.resolve(recorded: nil, directoryAdded: arrival, created: old, observedAt: observation, isExisting: true) == arrival)
    try check("Known additions keep their date even if directory metadata changes",
        AddedDate.resolve(recorded: old, directoryAdded: arrival, created: observation, observedAt: observation, isExisting: false) == old)
    try check("Existing files can bootstrap from local creation dates",
        AddedDate.resolve(recorded: nil, directoryAdded: nil, created: old, observedAt: observation, isExisting: true) == old)
    try check("New discoveries ignore inherited creation dates without an arrival date",
        AddedDate.resolve(recorded: nil, directoryAdded: nil, created: old, observedAt: observation, isExisting: false) == observation)
    try check("Missing old file dates fall back to discovery time",
        AddedDate.resolve(recorded: nil, directoryAdded: nil, created: nil, observedAt: observation, isExisting: true) == observation)
    try check("Invalid or future filesystem dates do not sort ahead of real additions",
        AddedDate.resolve(recorded: nil, directoryAdded: observation.addingTimeInterval(1), created: .distantPast,
            observedAt: observation, isExisting: true) == observation)
    try check("Recorded dates survive a backward clock adjustment",
        AddedDate.resolve(recorded: observation, directoryAdded: nil, created: nil, observedAt: old, isExisting: false) == observation)

    let fm = FileManager.default
    let base = FileLocation.canonicalURL(fm.temporaryDirectory).appendingPathComponent("rose-added-checks-\(UUID().uuidString)", isDirectory: true)
    let vault = base.appendingPathComponent("Vault", isDirectory: true)
    try fm.createDirectory(at: vault, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    var root = VaultRoot(url: vault)
    func asset(_ name: String, added: Date?, created: Date, modified: Date) -> ImageAsset {
        ImageAsset(url: vault.appendingPathComponent(name), rootID: root.id, relativePath: name,
            byteSize: 100, modifiedAt: modified, createdAt: created, width: 40, height: 30, addedAt: added)
    }
    let older = asset("A.png", added: old, created: observation, modified: observation)
    let newer = asset("Z.png", added: arrival, created: old, modified: old)
    func sorted(_ entries: [ImageAsset], ascending: Bool = false, location: LibraryLocation = .all, recent: [String] = []) -> [ImageAsset] {
        LibraryQuery.filter(entries, location: location, search: "", recursive: true, sort: .added,
            ascending: ascending, recentPaths: recent)
    }
    try check("Date added sorts newest first independently of filename, creation, and modification",
        sorted([older, newer]).map(\.id) == [newer.id, older.id])
    try check("Date added can reverse to oldest first", sorted([newer, older], ascending: true).map(\.id) == [older.id, newer.id])
    let tie = asset("B.png", added: old, created: old, modified: old)
    try check("Equal added dates use a deterministic path order", sorted([tie, older]).map(\.id) == [older.id, tie.id])
    let legacy = asset("Legacy.png", added: nil, created: arrival, modified: old)
    try check("A warm pre-feature index has an estimated order before rescanning",
        sorted([older, legacy]).first?.id == legacy.id)
    try check("Recently viewed keeps its viewing order when Date added is selected",
        sorted([older, newer], location: .recent, recent: [older.id, newer.id]).map(\.id) == [older.id, newer.id])
    try check("Date added is available without changing the Name default", AssetSort.allCases.contains(.added) && AssetSort.allCases.first == .name)

    let image = vault.appendingPathComponent("Existing.png")
    try writePNG(image)
    try fm.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: image.path)
    let scanTime = Date()
    let initial = LibraryIndexer.scan(root: root, cached: [], observedAt: scanTime)
    var indexed = initial.assets[0]
    let values = try image.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
    if let native = values.addedToDirectoryDate, native.timeIntervalSince1970 > 0, native <= scanTime {
        try check("Indexing reads actual folder-arrival metadata when the volume supplies it", indexed.addedAt == native)
    } else {
        try check("Volumes without arrival metadata bootstrap an existing file safely", indexed.addedAt == values.creationDate || indexed.addedAt == scanTime)
    }
    indexed.addedAt = arrival
    root.firstIndexedAt = scanTime
    let warm = LibraryIndexer.scan(root: root, cached: [indexed])
    try check("Warm metadata reuse retains the recorded addition date", warm.assets[0].addedAt == arrival)
    try writePNG(image, width: 91, height: 47)
    let edited = LibraryIndexer.scan(root: root, cached: warm.assets)
    try check("Editing an image updates its dimensions without making it newly added",
        edited.assets[0].width == 91 && edited.assets[0].addedAt == arrival)
    var unmigrated = edited.assets[0]; unmigrated.addedAt = nil
    let migrated = LibraryIndexer.scan(root: root, cached: [unmigrated])
    try check("Legacy cached entries gain an added date even on the unchanged-file path", migrated.assets[0].addedAt != nil)

    let newImage = vault.appendingPathComponent("New.png")
    try writePNG(newImage)
    try fm.setAttributes([.creationDate: old], ofItemAtPath: newImage.path)
    let discoveredAt = Date()
    let newValues = try newImage.resourceValues(forKeys: [.addedToDirectoryDateKey])
    let discovered = LibraryIndexer.scan(root: root, cached: edited.assets, observedAt: discoveredAt)
    let newAsset = discovered.assets.first { $0.url == newImage }!
    if let native = newValues.addedToDirectoryDate, native.timeIntervalSince1970 > 0, native <= discoveredAt {
        try check("A new file uses its folder arrival even with an old creation date", newAsset.addedAt == native)
    } else {
        try check("A new file without folder arrival uses discovery, not old creation", newAsset.addedAt == discoveredAt)
    }

    var state = LibraryState(); state.roots = [root]; state.assets = discovered.assets
    let directory = base.appendingPathComponent("State", isDirectory: true)
    try StateStore.save(state, to: directory)
    let reloaded = try StateStore.load(from: directory)
    try check("Added dates and initial-scan markers survive a state save and reload",
        reloaded.assets == state.assets && reloaded.roots[0].firstIndexedAt == root.firstIndexedAt)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    json["assets"] = (json["assets"] as! [[String: Any]]).map { entry -> [String: Any] in
        var oldEntry = entry; oldEntry.removeValue(forKey: "addedAt"); return oldEntry
    }
    json["roots"] = (json["roots"] as! [[String: Any]]).map { entry -> [String: Any] in
        var oldEntry = entry; oldEntry.removeValue(forKey: "firstIndexedAt"); return oldEntry
    }
    let oldState = try JSONDecoder().decode(LibraryState.self, from: JSONSerialization.data(withJSONObject: json))
    try check("Libraries saved before Date added still decode without losing assets",
        oldState.assets.count == state.assets.count && oldState.assets.allSatisfy { $0.addedAt == nil } && oldState.roots[0].firstIndexedAt == nil)
    let offlineRoot = VaultRoot(url: base.appendingPathComponent("Offline"), firstIndexedAt: scanTime)
    let offline = LibraryIndexer.scan(root: offlineRoot, cached: discovered.assets)
    try check("Offline roots retain their recorded dates", !offline.isAvailable && offline.assets == discovered.assets)
}
