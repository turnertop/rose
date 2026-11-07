import AppKit
import Combine
import SwiftUI

extension InteractionChecks {
    @MainActor
    static func automaticAppearance() throws {
        let suite = "app.rose.appearance-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func preference() -> AppStorage<Bool> {
            AppStorage(wrappedValue: AutomaticAppearancePreference.defaultValue,
                       AutomaticAppearancePreference.key, store: defaults)
        }
        try check("Automatic appearance starts off for existing installations", !preference().wrappedValue)
        defaults.set("dark", forKey: "rose.appearance")
        preference().wrappedValue = true
        try check("The day/night toggle survives a fresh preference reader", preference().wrappedValue)
        preference().wrappedValue = false
        try check("Turning automatic appearance off is persisted", !preference().wrappedValue)
        try check("The automatic toggle does not overwrite the manual appearance", defaults.string(forKey: "rose.appearance") == "dark")

        let parser = ISO8601DateFormatter()
        func date(_ text: String) -> Date { parser.date(from: text)! }
        func calendar(_ offset: Int) -> Calendar {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: offset * 3600)!
            return value
        }
        let utc = calendar(0)
        for (time, night) in [("00:40:00", true), ("06:59:59", true), ("07:00:00", false),
                              ("12:00:00", false), ("18:59:59", false), ("19:00:00", true), ("23:59:59", true)] {
            try check("Local \(time) chooses the expected day/night palette",
                      AutomaticAppearancePreference.isNight(at: date("2026-11-07T\(time)Z"), calendar: utc) == night)
        }
        let instant = date("2026-11-07T08:40:00Z")
        try check("A local 12:40 AM chooses dark rose", AutomaticAppearancePreference.isNight(at: instant, calendar: calendar(-8)))
        try check("A computer three hours ahead uses its own 3:40 AM", AutomaticAppearancePreference.isNight(at: instant, calendar: calendar(-5)))
        try check("A computer nine hours ahead uses its own 9:40 AM", !AutomaticAppearancePreference.isNight(at: instant, calendar: calendar(1)))
        var daylight = Calendar(identifier: .gregorian)
        daylight.timeZone = TimeZone(identifier: "America/Vancouver")!
        try check("Pink begins at local 7 AM after the spring DST change",
                  !AutomaticAppearancePreference.isNight(at: date("2026-03-08T14:00:00Z"), calendar: daylight))
        try check("Pink begins at local 7 AM after the autumn DST change",
                  !AutomaticAppearancePreference.isNight(at: date("2026-11-01T15:00:00Z"), calendar: daylight))

        var now = date("2026-11-07T06:59:30Z")
        var zone = utc
        let center = NotificationCenter(), workspace = NotificationCenter()
        let clock = AppearanceClock(now: { now }, calendar: { zone }, center: center, workspaceCenter: workspace)
        var publications = 0
        let subscription = clock.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel(); clock.setEnabled(false) }
        clock.setEnabled(true)
        try check("A fresh enabled clock immediately uses the current local time", clock.isNight)
        now = date("2026-11-07T07:00:00Z")
        clock.refresh()
        try check("The live clock changes to pink at the morning boundary", !clock.isNight && publications == 1)
        clock.refresh(); clock.refresh()
        try check("Steady clock checks do not publish gallery invalidations", publications == 1)
        now = date("2026-11-07T19:00:00Z")
        center.post(name: .NSSystemClockDidChange, object: nil)
        try check("Changing the system clock reevaluates the live palette", clock.isNight && publications == 2)
        now = instant; zone = calendar(1)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try check("Changing time zones reevaluates the live palette", !clock.isNight)
        now = date("2026-11-07T20:00:00Z")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try check("Waking after sunset reevaluates immediately", clock.isNight)
        now = date("2026-11-07T12:00:00Z")
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try check("Returning to Rose reevaluates the current time", !clock.isNight)
        clock.setEnabled(false)
        now = date("2026-11-07T23:00:00Z")
        center.post(name: .NSSystemClockDidChange, object: nil); clock.refresh()
        try check("Disabled automatic appearance stops its clock updates", !clock.isEnabled && !clock.isNight)
        clock.setEnabled(true)
        try check("Reenabling uses the current time instead of the old palette", clock.isNight)
        clock.setEnabled(false); zone = utc
        now = date("2026-11-07T06:59:59Z").addingTimeInterval(0.9)
        clock.setEnabled(true)
        now = date("2026-11-07T07:00:00Z")
        let deadline = Date(timeIntervalSinceNow: 2)
        while clock.isNight && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        try check("The scheduled timer changes appearance without user interaction", !clock.isNight)
    }
}
