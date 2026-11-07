import AppKit

extension InteractionChecks {
    @MainActor
    static func viewerContextMenu() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let clip = CenteringClipView()
        let image = PannableImageView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1600))
        image.scrollView = scroll; scroll.contentView = clip; scroll.documentView = image
        window.contentView!.addSubview(scroll)
        let rightClick = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 200, y: 150), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let controlClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 200, y: 150), modifierFlags: [.control],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        try check("A detached viewer has no image actions", image.menu(for: rightClick) == nil)
        var copied: [String] = [], revealed: [String] = []
        func configure(_ openedImage: String) {
            scroll.configureImageActions(copy: { copied.append(openedImage) }, reveal: { revealed.append(openedImage) })
        }
        configure("first.png")
        let menu = image.menu(for: rightClick)!
        try check("Right-clicking the image offers Copy Image and Show in Finder", menu.items.map(\.title) == ["Copy Image", "Show in Finder"])
        try check("The ready-made menu is reused on subsequent clicks", image.menu(for: rightClick) === menu)
        try check("Opening the menu does not load contextual menu plug-ins or validate image export", !menu.allowsContextMenuPlugIns && !menu.autoenablesItems)
        try check("The menu needs no image or symbol loading", menu.items.allSatisfy { $0.image == nil && $0.representedObject == nil })
        try check("Menu preparation does not execute image actions", copied.isEmpty && revealed.isEmpty)
        try check("Both image actions are enabled", menu.items.allSatisfy(\.isEnabled))
        try check("Control-click has the same viewer actions", image.menu(for: controlClick)?.items.map(\.title) == menu.items.map(\.title))
        try check("The letterboxed area has the same actions", clip.menu(for: rightClick)?.items.map(\.title) == menu.items.map(\.title))
        try check("The viewer scroll surface has the same actions", scroll.menu(for: rightClick)?.items.map(\.title) == menu.items.map(\.title))
        scroll.setMagnification(2, centeredAt: NSPoint(x: 700, y: 600))
        let origin = scroll.contentView.bounds.origin
        menu.performActionForItem(at: 0); menu.performActionForItem(at: 1)
        try check("Menu commands target the opened image", copied == ["first.png"] && revealed == ["first.png"])
        try check("Image actions preserve zoom and pan", scroll.magnification == 2 && scroll.contentView.bounds.origin == origin)
        configure("second.png")
        try check("Navigating images preserves the prepared menu", image.menu(for: rightClick) === menu)
        menu.performActionForItem(at: 0); menu.performActionForItem(at: 1)
        try check("A retained menu follows the newly opened image", copied.last == "second.png" && revealed.last == "second.png")
        scroll.configureImageActions(copy: nil, reveal: nil)
        menu.performActionForItem(at: 0); menu.performActionForItem(at: 1)
        try check("Closing the viewer retires old menu actions", copied.count == 2 && revealed.count == 2 && image.menu(for: rightClick) == nil)
        try check("Viewer menu fixtures remain offscreen", !window.isVisible)
    }
}
