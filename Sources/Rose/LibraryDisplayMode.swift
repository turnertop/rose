enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case fill, fit, list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .list: return "List"
        }
    }

    var help: String {
        switch self {
        case .fill: return "Fill each thumbnail tile, cropping edges · ⌘1"
        case .fit: return "Show whole images in rows with natural proportions · ⌘2"
        case .list: return "Browse images in a compact list · ⌘3"
        }
    }
}
