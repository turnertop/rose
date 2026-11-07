import Foundation

enum ViewerScrollZoomPreference {
    static let key = "rose.viewer.twoFingerScrollZoom"
    static let defaultValue = false
}

enum ThumbnailSizePreference {
    static let key = "rose.thumbnailSize"
    static let range: ClosedRange<Double> = 125...300
    static let defaultValue = 190.0

    static func load(from defaults: UserDefaults = .standard) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return defaultValue }
        return bounded(number.doubleValue)
    }

    static func save(_ value: Double, to defaults: UserDefaults = .standard) {
        defaults.set(bounded(value), forKey: key)
    }

    private static func bounded(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : defaultValue
    }
}

enum SortPreference {
    static let key = "rose.sortOrder"

    struct Value: Equatable {
        let field: String
        let ascending: Bool
    }

    static func load(validFields: [String], from defaults: UserDefaults = .standard) -> Value? {
        guard let saved = defaults.dictionary(forKey: key),
              let field = saved["field"] as? String, validFields.contains(field),
              let ascending = saved["ascending"] as? Bool else { return nil }
        return Value(field: field, ascending: ascending)
    }

    static func save(field: String, ascending: Bool, to defaults: UserDefaults = .standard) {
        // One preferences value keeps the field and its direction together.
        defaults.set(["field": field, "ascending": ascending], forKey: key)
    }
}
