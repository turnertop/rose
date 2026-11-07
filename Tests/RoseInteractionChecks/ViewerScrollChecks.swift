import AppKit
import SwiftUI

extension InteractionChecks {
    @MainActor
    static func viewerScrolling() throws {
        let suite = "app.rose.viewer-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func preference() -> AppStorage<Bool> {
            AppStorage(wrappedValue: ViewerScrollZoomPreference.defaultValue, ViewerScrollZoomPreference.key, store: defaults)
        }
        let setting = preference()
        try check("Two-finger viewer zoom starts disabled", !setting.wrappedValue)
        setting.wrappedValue = true
        try check("The enabled viewer gesture preference survives a fresh reader", preference().wrappedValue)
        setting.wrappedValue = false
        try check("The disabled viewer gesture preference is saved too", !preference().wrappedValue)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let owner = ViewerWindowReference()
        let scroll = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scroll.ownerWindow = owner
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.contentView = CenteringClipView()
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 4000, height: 4000))
        window.contentView!.addSubview(scroll)
        scroll.layoutSubtreeIfNeeded()
        var zoomEvents = 0
        scroll.onUserZoom = { zoomEvents += 1 }

        func reset() {
            scroll.setMagnification(1, centeredAt: NSPoint(x: 2000, y: 2000))
            scroll.contentView.scroll(to: NSPoint(x: 1000, y: 1000))
            scroll.reflectScrolledClipView(scroll.contentView)
            zoomEvents = 0
        }
        func gesture(_ delta: CGFloat, inverted: Bool = false, momentum: NSEvent.Phase = [],
                     precise: Bool = true, modifiers: NSEvent.ModifierFlags = [], horizontal: CGFloat = 0) -> FixtureScrollEvent {
            let event = FixtureScrollEvent()
            event.vertical = delta; event.horizontal = horizontal
            event.inverted = inverted; event.momentum = momentum
            event.precise = precise; event.modifiers = modifiers
            event.point = scroll.convert(NSPoint(x: 320, y: 240), to: nil)
            return event
        }

        try check("The native viewer starts in scroll-to-pan mode", !scroll.twoFingerScrollZoom)
        scroll.twoFingerScrollZoom = true
        try check("Enabling scroll zoom retains native pinch magnification", scroll.allowsMagnification)
        reset()
        scroll.scrollWheel(with: gesture(100))
        let upwardZoom = scroll.magnification
        try check("An upward gesture increases actual viewer magnification", upwardZoom > 1 && zoomEvents == 1)
        scroll.scrollWheel(with: gesture(-100))
        try check("An equal downward gesture reverses the zoom", abs(scroll.magnification - 1) < 0.000001)
        reset()
        scroll.scrollWheel(with: gesture(-100, inverted: true))
        try check("Upward zoom stays consistent with Natural Scrolling enabled", abs(scroll.magnification - upwardZoom) < 0.000001)
        scroll.scrollWheel(with: gesture(100, inverted: true))
        try check("Downward zoom stays consistent with Natural Scrolling enabled", abs(scroll.magnification - 1) < 0.000001)

        reset()
        scroll.scrollWheel(with: gesture(100, momentum: .changed))
        try check("Scroll momentum does not continue zooming after fingers lift", scroll.magnification == 1 && zoomEvents == 0)
        let origin = scroll.contentView.bounds.origin
        scroll.scrollWheel(with: gesture(0, horizontal: 100))
        try check("Horizontal-only gestures do not zoom or drift in zoom mode", scroll.magnification == 1 && scroll.contentView.bounds.origin == origin && zoomEvents == 0)
        scroll.scrollWheel(with: gesture(5))
        try check("Small gesture deltas make gradual zoom changes", scroll.magnification > 1 && scroll.magnification < 1.1)

        reset()
        scroll.scrollWheel(with: gesture(100000))
        try check("Strong upward gestures respect the existing maximum zoom", scroll.magnification == 16)
        scroll.scrollWheel(with: gesture(-100000))
        try check("Strong downward gestures respect the existing minimum zoom", abs(scroll.magnification - 0.01) < 0.000001)

        scroll.twoFingerScrollZoom = false
        reset()
        let pixelEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 40, wheel2: 0, wheel3: 0)!
        pixelEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let nativeScroll = NSEvent(cgEvent: pixelEvent)!
        try check("The pan fixture uses a real precise scroll event", nativeScroll.hasPreciseScrollingDeltas)
        let beforePan = scroll.contentView.bounds.origin
        scroll.scrollWheel(with: nativeScroll)
        // Native panning animates on the run loop even in an offscreen fixture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        try check("Disabling the toggle restores native panning without zoom", scroll.magnification == 1 && scroll.contentView.bounds.origin != beforePan && zoomEvents == 0)
        reset()
        scroll.scrollWheel(with: gesture(5, modifiers: [.option]))
        try check("Option–scroll still zooms with the setting off", scroll.magnification > 1 && zoomEvents == 1)
        reset()
        scroll.scrollWheel(with: gesture(5, precise: false))
        try check("Mouse-wheel zoom retains its existing behavior", scroll.magnification > 1 && zoomEvents == 1)

        try check("The viewer records its actual owning window", owner.window === window)
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        defer { settings.close() }
        func space(in target: NSWindow) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: target.windowNumber, context: nil, characters: " ",
                             charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        }
        try check("Viewer shortcuts stay scoped to the viewer's window", owner.owns(space(in: window)) && !owner.owns(space(in: settings)))
        try check("Viewer and Settings fixtures were never displayed", !window.isVisible && !settings.isVisible)
    }
}

private final class FixtureScrollEvent: NSEvent {
    var vertical: CGFloat = 0
    var horizontal: CGFloat = 0
    var inverted = false
    var momentum: NSEvent.Phase = []
    var precise = true
    var modifiers: NSEvent.ModifierFlags = []
    var point = NSPoint.zero
    override var type: NSEvent.EventType { .scrollWheel }
    override var scrollingDeltaY: CGFloat { vertical }
    override var scrollingDeltaX: CGFloat { horizontal }
    override var isDirectionInvertedFromDevice: Bool { inverted }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var modifierFlags: NSEvent.ModifierFlags { modifiers }
    override var locationInWindow: NSPoint { point }
}
