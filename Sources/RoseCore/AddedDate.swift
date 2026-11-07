import Foundation

/// Preserve a known arrival date; bootstrap older libraries from local file dates.
public enum AddedDate {
    public static func resolve(recorded: Date?, directoryAdded: Date?, created: Date?,
                               observedAt: Date, isExisting: Bool) -> Date {
        if let recorded, recorded.timeIntervalSince1970.isFinite, recorded.timeIntervalSince1970 > 0 {
            return recorded
        }
        if let directoryAdded, usable(directoryAdded, observedAt: observedAt) { return directoryAdded }
        if isExisting, let created, usable(created, observedAt: observedAt) { return created }
        return observedAt
    }

    private static func usable(_ date: Date, observedAt: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 > 0 && date <= observedAt
    }
}
