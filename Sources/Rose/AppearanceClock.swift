import AppKit
import Combine
import Foundation

enum AutomaticAppearancePreference {
    static let key = "rose.automaticDayNight"
    static let defaultValue = false

    static func isNight(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }
}

@MainActor
final class AppearanceClock: ObservableObject {
    @Published private(set) var isNight: Bool
    private(set) var isEnabled = false
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let center: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         center: NotificationCenter = .default,
         workspaceCenter: NotificationCenter? = nil) {
        self.now = now; self.calendar = calendar; self.center = center
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        isNight = AutomaticAppearancePreference.isNight(at: now(), calendar: calendar())
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        timer?.invalidate(); timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        guard enabled else { return }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange,
                     NSApplication.didBecomeActiveNotification] {
            observe(name, on: center)
        }
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter)
        refresh()
    }

    func refresh() {
        guard isEnabled else { return }
        let date = now()
        let night = AutomaticAppearancePreference.isNight(at: date, calendar: calendar())
        // Clock checks must not invalidate the gallery when the palette is unchanged.
        if isNight != night { isNight = night }
        timer?.invalidate()
        let remainder = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let delay = max(0.1, 60 - remainder)
        let next = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        next.tolerance = 0.2
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, observer))
    }

    deinit {
        timer?.invalidate()
        observers.forEach { $0.0.removeObserver($0.1) }
    }
}
