import Foundation

/// Annotations travel with the image as an ordinary UTF-8 Markdown file.
/// appendingPathExtension keeps photo.jpg.md distinct from photo.png.md.
public enum SidecarStore {
    public static func url(for imageURL: URL) -> URL { imageURL.appendingPathExtension("md") }

    public static func read(for imageURL: URL) -> ImageAnnotation {
        guard let text = try? String(contentsOf: url(for: imageURL), encoding: .utf8) else { return .init() }
        return decode(text)
    }

    public static func decode(_ text: String) -> ImageAnnotation {
        let parts = split(text)
        var annotation = ImageAnnotation(note: parts.body)
        for (index, line) in parts.header.enumerated() {
            if line.hasPrefix("favorite:") { annotation.isFavorite = value(line) == "true" }
            if line.hasPrefix("tags:") {
                let raw = value(line)
                if let data = raw.data(using: .utf8), let tags = try? JSONDecoder().decode([String].self, from: data) {
                    annotation.tags = tags
                } else if raw.isEmpty {
                    annotation.tags = parts.header.dropFirst(index + 1).prefix { $0.hasPrefix(" ") || $0.hasPrefix("\t") }
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("- ") }
                        .map { scalar(String($0.dropFirst(2))) }.filter { !$0.isEmpty }
                } else {
                    annotation.tags = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                        .split(separator: ",").map { scalar(String($0)) }.filter { !$0.isEmpty }
                }
            }
        }
        return annotation
    }

    public static func write(_ annotation: ImageAnnotation, for imageURL: URL) throws {
        let destination = url(for: imageURL)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        // A read error must never cause an existing note to be overwritten with an empty file.
        let existing = exists ? try String(contentsOf: destination, encoding: .utf8) : ""
        let content = encode(annotation, preserving: existing)
        try content.write(to: destination, atomically: true, encoding: .utf8)
    }

    public static func encode(_ annotation: ImageAnnotation, preserving existing: String = "") -> String {
        let parts = split(existing)
        var retained: [String] = []
        var skippingManagedField = false
        for line in parts.header {
            if line.hasPrefix("tags:") || line.hasPrefix("favorite:") || line.hasPrefix("rose:") { skippingManagedField = true; continue }
            if skippingManagedField, line.hasPrefix(" ") || line.hasPrefix("\t") { continue }
            skippingManagedField = false
            retained.append(line)
        }
        let tagData = (try? JSONEncoder().encode(annotation.tags)) ?? Data("[]".utf8)
        let tags = String(decoding: tagData, as: UTF8.self)
        let header = (["rose: 1", "favorite: \(annotation.isFavorite)", "tags: \(tags)"] + retained).joined(separator: "\n")
        return "---\n\(header)\n---\n" + annotation.note
    }

    private static func value(_ line: String) -> String {
        String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func scalar(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 { return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return text
    }

    private static func split(_ text: String) -> (header: [String], body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("---\n---\n") { return ([], String(normalized.dropFirst(8))) }
        guard normalized.hasPrefix("---\n"), let end = normalized.range(of: "\n---\n", range: normalized.index(normalized.startIndex, offsetBy: 3)..<normalized.endIndex) else {
            return ([], normalized)
        }
        let headerStart = normalized.index(normalized.startIndex, offsetBy: 4)
        let header = String(normalized[headerStart..<end.lowerBound]).components(separatedBy: "\n")
        return (header, String(normalized[end.upperBound...]))
    }
}
