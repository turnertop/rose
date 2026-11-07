import AppKit

@MainActor
final class ViewerImageActions: NSObject {
    private var copyImage: (() -> Void)?
    private var showInFinder: (() -> Void)?
    private let contextMenu = NSMenu()

    override init() {
        super.init()
        // Keep preparation off the click path. This menu needs no system services,
        // contextual plug-ins, image export, or symbol loading to show two actions.
        contextMenu.autoenablesItems = false
        contextMenu.allowsContextMenuPlugIns = false
        for (title, action) in [
            ("Copy Image", #selector(copyOpenedImage(_:))),
            ("Show in Finder", #selector(revealOpenedImage(_:)))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = false
            contextMenu.addItem(item)
        }
    }

    func configure(copy: (() -> Void)?, reveal: (() -> Void)?) {
        copyImage = copy; showInFinder = reveal
        contextMenu.item(at: 0)?.isEnabled = copy != nil
        contextMenu.item(at: 1)?.isEnabled = reveal != nil
        if copy == nil && reveal == nil { contextMenu.cancelTrackingWithoutAnimation() }
    }

    func menu() -> NSMenu? {
        guard copyImage != nil || showInFinder != nil else { return nil }
        return contextMenu
    }

    @objc private func copyOpenedImage(_ sender: Any?) { copyImage?() }
    @objc private func revealOpenedImage(_ sender: Any?) { showInFinder?() }
}

final class ViewerWindowReference {
    weak var window: NSWindow?

    @MainActor func owns(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        return event.window === window
    }
}

final class CenteringClipView: NSClipView {
    weak var imageActions: ViewerImageActions?
    override func menu(for event: NSEvent) -> NSMenu? { imageActions?.menu() }
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
    private let imageActions = ViewerImageActions()

    func configureImageActions(copy: (() -> Void)?, reveal: (() -> Void)?) {
        imageActions.configure(copy: copy, reveal: reveal)
        (contentView as? CenteringClipView)?.imageActions = imageActions
        (documentView as? PannableImageView)?.imageActions = imageActions
    }

    override func menu(for event: NSEvent) -> NSMenu? { imageActions.menu() }
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
    weak var imageActions: ViewerImageActions?
    private var previousPoint: NSPoint?
    override func menu(for event: NSEvent) -> NSMenu? { imageActions?.menu() }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { super.rightMouseDown(with: event); return }
        // Bypass NSImageView's built-in image contextual handling.
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
            return
        }
        previousPoint = event.locationInWindow; NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previousPoint, let scrollView else { return }
        let current = event.locationInWindow
        let scale = scrollView.magnification
        let origin = scrollView.contentView.bounds.origin
        scrollView.contentView.scroll(to: NSPoint(x: origin.x - (current.x - previousPoint.x) / scale, y: origin.y - (current.y - previousPoint.y) / scale))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        self.previousPoint = current
    }
    override func mouseUp(with event: NSEvent) {
        guard previousPoint != nil else { return }
        previousPoint = nil; NSCursor.pop()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
