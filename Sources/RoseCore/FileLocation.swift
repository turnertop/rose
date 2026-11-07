import Foundation
import Darwin

public enum FileLocation {
    /// Foundation can spell the same macOS temp folder as either /var or /private/var.
    /// Use the kernel's path so directory enumeration and sidebar matching agree.
    public static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = url.path.withCString({ realpath($0, nil) }) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: url.hasDirectoryPath)
    }
}
