import Foundation

public enum StateStore {
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["ROSE_DATA_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rose", isDirectory: true)
    }

    public static func load(from directory: URL = directory) throws -> LibraryState {
        let file = directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return LibraryState() }
        return try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: file))
    }

    public static func save(_ state: LibraryState, to directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }
}
