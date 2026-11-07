import AppKit
import SwiftUI

extension InteractionChecks {
    @MainActor
    static func selectionClicks() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = window.contentView!
        let keyboard = GalleryKeyboard()
        let field = RoseSearchTextField(frame: NSRect(x: 330, y: 430, width: 290, height: 22))
        field.keyboard = keyboard
        var query = "d"
        field.stringValue = query
        field.onTextChange = { query = $0 }
        var enabled = true
        field.isBrowsingEnabled = { enabled }
        content.addSubview(field)

        let items = FixtureItems()
        let collection = RoseCollectionView(frame: NSRect(x: 0, y: 0, width: 440, height: 280))
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 90, height: 100)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.register(FixtureItem.self, forItemWithIdentifier: FixtureItems.identifier)
        collection.dataSource = items
        var modelHasSelection = false
        var primary: IndexPath?
        var clears = 0
        var opened = 0
        collection.onClearSelection = { modelHasSelection = false; primary = nil; clears += 1 }
        collection.onOpen = { opened += 1 }
        keyboard.collection = collection
        keyboard.onClearSelection = collection.onClearSelection
        let scroll = NSScrollView(frame: NSRect(x: 180, y: 20, width: 440, height: 280))
        scroll.hasVerticalScroller = true
        scroll.documentView = collection
        content.addSubview(scroll)
        collection.reloadData()
        scroll.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        let selected = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)
        let firstFrame = layout.layoutAttributesForItem(at: selected)!.frame
        let secondFrame = layout.layoutAttributesForItem(at: second)!.frame
        let gap = NSPoint(x: (firstFrame.maxX + secondFrame.minX) / 2, y: firstFrame.midY)

        func select(_ paths: Set<IndexPath> = [selected]) {
            collection.selectionIndexPaths = paths
            modelHasSelection = !paths.isEmpty
            primary = paths.sorted().first
        }
        func click(_ point: NSPoint, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: modifiers, timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                               clickCount: 1, pressure: 1)!
        }
        let imageClick = click(collection.convert(NSPoint(x: firstFrame.midX, y: firstFrame.midY), to: nil))
        select()
        try check("Clicking an image is passed through without clearing selection", field.routeSearchEvent(imageClick) === imageClick && collection.selectionIndexPaths == [selected] && modelHasSelection && clears == 0)
        try check("The whitespace fixture is outside every image card", collection.indexPathForItem(at: gap) == nil)
        let gapPoint = collection.convert(gap, to: nil)
        for flags: NSEvent.ModifierFlags in [.command, .shift, .control] {
            let modifiedClick = click(gapPoint, flags)
            _ = field.routeSearchEvent(modifiedClick)
            try check("Modified background clicks retain native selection handling (\(flags.rawValue))", collection.selectionIndexPaths == [selected] && modelHasSelection && clears == 0)
        }
        select([selected, second])
        let gapClick = click(gapPoint)
        try check("A plain gallery-gap click clears the whole visible selection", field.routeSearchEvent(gapClick) === gapClick && collection.selectionIndexPaths.isEmpty)
        try check("Gallery-gap deselection also clears the inspector/model selection", !modelHasSelection && primary == nil && clears == 1)
        try check("Deselection leaves the search filter intact", query == "d" && field.stringValue == "d")
        let beforePage = scroll.contentView.bounds.minY
        let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: " ",
                                    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        if let event = field.routeSearchEvent(space) { window.firstResponder?.keyDown(with: event) }
        try check("Space scrolls immediately after clicking an image gap", scroll.contentView.bounds.minY > beforePage && opened == 0)

        let title = NSTextField(labelWithString: "All images")
        title.frame = NSRect(x: 200, y: 350, width: 200, height: 30)
        content.addSubview(title)
        select()
        let headerClick = click(NSPoint(x: 230, y: 365))
        _ = field.routeSearchEvent(headerClick)
        try check("A heading clears selection even when the gallery has scrolled", collection.selectionIndexPaths.isEmpty && !modelHasSelection && primary == nil)

        let action = FixtureButtonAction()
        let button = NSButton(title: "Favorite", target: action, action: #selector(FixtureButtonAction.clicked))
        button.frame = NSRect(x: 15, y: 300, width: 140, height: 24)
        content.addSubview(button)
        select()
        let controlClick = click(button.convert(NSPoint(x: 40, y: 10), to: nil))
        try check("Native action buttons keep the selected image", field.routeSearchEvent(controlClick) === controlClick && modelHasSelection && collection.selectionIndexPaths == [selected])
        button.performClick(nil)
        try check("Image actions still run after the click is routed", action.clicks == 1)
        let slider = NSSlider(frame: NSRect(x: 200, y: 315, width: 140, height: 24))
        content.addSubview(slider)
        _ = field.routeSearchEvent(click(slider.convert(NSPoint(x: 60, y: 12), to: nil)))
        try check("Native thumbnail sliders keep image selection", modelHasSelection && collection.selectionIndexPaths == [selected])
        slider.removeFromSuperview()

        let hosted = NSHostingView(rootView:
            HStack(spacing: 0) {
                Button("View control") {}.buttonStyle(.plain).frame(width: 120, height: 44)
                    .preservesImageSelection(using: keyboard)
                Color.clear.frame(width: 120, height: 44)
            }.frame(width: 240, height: 44)
        )
        hosted.frame = NSRect(x: 20, y: 390, width: 240, height: 44)
        content.addSubview(hosted)
        hosted.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        let swiftUIControlClick = click(NSPoint(x: 70, y: 412))
        try check("A real SwiftUI control registers its protected visible geometry", keyboard.selectionClickTargets.preservesSelection(at: swiftUIControlClick))
        _ = field.routeSearchEvent(swiftUIControlClick)
        try check("Hosted SwiftUI controls retain the selected image", modelHasSelection && collection.selectionIndexPaths == [selected])
        let hostedBlankClick = click(NSPoint(x: 200, y: 412))
        try check("Blank space beside a SwiftUI control stays unprotected", !keyboard.selectionClickTargets.preservesSelection(at: hostedBlankClick))
        _ = field.routeSearchEvent(hostedBlankClick)
        try check("Blank hosted background clears both grid and model selection", !modelHasSelection && primary == nil && collection.selectionIndexPaths.isEmpty)
        hosted.removeFromSuperview()
        try check("Removed controls no longer protect their former location", !keyboard.selectionClickTargets.preservesSelection(at: swiftUIControlClick))

        let sideScroll = NSScrollView(frame: NSRect(x: 10, y: 20, width: 140, height: 100))
        let sideDocument = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 400))
        let clippedControl = SelectionProtectionView(frame: NSRect(x: 0, y: 150, width: 140, height: 40))
        clippedControl.targets = keyboard.selectionClickTargets
        sideDocument.addSubview(clippedControl)
        sideScroll.documentView = sideDocument
        content.addSubview(sideScroll)
        sideScroll.layoutSubtreeIfNeeded()
        sideScroll.contentView.scroll(to: .zero)
        sideScroll.reflectScrolledClipView(sideScroll.contentView)
        let clippedPoint = clippedControl.convert(NSPoint(x: 40, y: 20), to: nil)
        let clippedClick = click(clippedPoint)
        let outsideClip = !sideScroll.contentView.bounds.contains(sideScroll.contentView.convert(clippedPoint, from: nil))
        try check("Clipped sidebar controls do not protect blank areas outside their scroll view", outsideClip && !keyboard.selectionClickTargets.preservesSelection(at: clippedClick))
        select()
        _ = field.routeSearchEvent(clippedClick)
        try check("Blank areas behind clipped controls still deselect", !modelHasSelection && collection.selectionIndexPaths.isEmpty)
        sideScroll.removeFromSuperview()

        select()
        field.requestSearchFocus(1)
        let editor = field.currentEditor()
        let searchClick = click(field.convert(NSPoint(x: 50, y: 10), to: nil))
        _ = field.routeSearchEvent(searchClick)
        try check("Search editing retains the selected image", window.firstResponder === editor && modelHasSelection && collection.selectionIndexPaths == [selected])
        enabled = false
        _ = field.routeSearchEvent(headerClick)
        try check("Viewer and modal overlays prevent background deselection", modelHasSelection && collection.selectionIndexPaths == [selected])
        enabled = true
        keyboard.collection = nil
        _ = field.routeSearchEvent(headerClick)
        try check("An empty-results view can still clear its model selection", !modelHasSelection && primary == nil)
        keyboard.collection = collection
        field.refreshBrowsingFocus()

        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        let otherClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 230, y: 365), modifierFlags: [], timestamp: 0,
                                           windowNumber: other.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        select()
        _ = field.routeSearchEvent(otherClick)
        try check("Clicking another window does not deselect this gallery", modelHasSelection && collection.selectionIndexPaths == [selected])
        try check("Selection fixtures were never displayed", !window.isVisible && !other.isVisible)
    }
}
