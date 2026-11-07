import AppKit

final class ViewerWindowReference {
    weak var window: NSWindow?

    @MainActor func owns(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        return event.window === window
    }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let document = documentView {
            if document.frame.width < rect.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
            if document.frame.height < rect.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        }
        return rect
    }
}

final class ZoomScrollView: NSScrollView {
    var onResize: (() -> Void)?
    var onUserZoom: (() -> Void)?
    var twoFingerScrollZoom = ViewerScrollZoomPreference.defaultValue
    var ownerWindow: ViewerWindowReference? {
        didSet { if let window { ownerWindow?.window = window } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureZoom()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureZoom()
    }

    private func configureZoom() {
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 16
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { ownerWindow?.window = window }
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); onResize?() }
    override func magnify(with event: NSEvent) { onUserZoom?(); super.magnify(with: event) }

    override func scrollWheel(with event: NSEvent) {
        let gestureZoom = twoFingerScrollZoom && event.hasPreciseScrollingDeltas
        guard gestureZoom || event.modifierFlags.contains(.option) || !event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }
        // Zoom stops when the fingers lift; scroll momentum must not keep magnifying.
        if gestureZoom, !event.momentumPhase.isEmpty { return }
        var delta = event.scrollingDeltaY
        if gestureZoom, event.isDirectionInvertedFromDevice { delta = -delta }
        guard delta.isFinite, delta != 0 else { return }
        onUserZoom?()
        let factor = exp(delta * (gestureZoom ? 0.005 : 0.025))
        let point = contentView.convert(event.locationInWindow, from: nil)
        setMagnification(min(maxMagnification, max(minMagnification, magnification * factor)), centeredAt: point)
    }
}

final class PannableImageView: NSImageView {
    weak var scrollView: NSScrollView?
    private var previousPoint: NSPoint?
    override func mouseDown(with event: NSEvent) { previousPoint = event.locationInWindow; NSCursor.closedHand.push() }
    override func mouseDragged(with event: NSEvent) {
        guard let previousPoint, let scrollView else { return }
        let current = event.locationInWindow
        let scale = scrollView.magnification
        let origin = scrollView.contentView.bounds.origin
        scrollView.contentView.scroll(to: NSPoint(x: origin.x - (current.x - previousPoint.x) / scale, y: origin.y - (current.y - previousPoint.y) / scale))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        self.previousPoint = current
    }
    override func mouseUp(with event: NSEvent) { previousPoint = nil; NSCursor.pop() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
