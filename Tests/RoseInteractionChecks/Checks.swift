import AppKit
import Foundation

private enum CheckFailure: Error { case failed(String) }
private var checkCount = 0

func check(_ message: String, _ condition: @autoclosure () -> Bool) throws {
    guard condition() else { throw CheckFailure.failed(message) }
    checkCount += 1
    print("✓ \(message)")
}

@main
enum InteractionChecks {
    @MainActor
    static func main() {
        do {
            try preferences()
            try searchKeyboard()
            try selectionClicks()
            try viewerScrolling()
            print("\n\(checkCount) interaction checks passed.")
        } catch {
            fputs("Interaction check failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func preferences() throws {
        let suite = "app.rose.interaction-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try check("A missing thumbnail preference retains the existing size", ThumbnailSizePreference.load(from: defaults) == 190)
        ThumbnailSizePreference.save(300, to: defaults)
        let reloaded = UserDefaults(suiteName: suite)!
        try check("The maximum slider size survives a fresh preference reader", ThumbnailSizePreference.load(from: reloaded) == 300)
        ThumbnailSizePreference.save(125, to: defaults)
        try check("The minimum slider size is saved", ThumbnailSizePreference.load(from: reloaded) == 125)
        ThumbnailSizePreference.save(238.5, to: defaults)
        try check("Intermediate slider values retain their precision", ThumbnailSizePreference.load(from: reloaded) == 238.5)
        defaults.set(900, forKey: ThumbnailSizePreference.key)
        try check("An out-of-range saved size is bounded", ThumbnailSizePreference.load(from: defaults) == 300)
        defaults.set("broken", forKey: ThumbnailSizePreference.key)
        try check("A malformed saved size falls back safely", ThumbnailSizePreference.load(from: defaults) == 190)
        defaults.set(Double.nan, forKey: ThumbnailSizePreference.key)
        try check("A nonfinite saved size falls back safely", ThumbnailSizePreference.load(from: defaults) == 190)

        let fields = ["Name", "Date added", "Date modified", "Date created", "File size", "Dimensions"]
        try check("A fresh installation has no saved sort override", SortPreference.load(validFields: fields, from: defaults) == nil)
        SortPreference.save(field: "Date added", ascending: false, to: defaults)
        try check("Newest-first Date added survives a fresh preference reader",
            SortPreference.load(validFields: fields, from: UserDefaults(suiteName: suite)!) == .init(field: "Date added", ascending: false))
        SortPreference.save(field: "Date added", ascending: true, to: defaults)
        try check("A saved oldest-first Date added choice is restored exactly",
            SortPreference.load(validFields: fields, from: reloaded) == .init(field: "Date added", ascending: true))
        SortPreference.save(field: "Name", ascending: false, to: defaults)
        try check("Name descending is remembered without forcing A to Z",
            SortPreference.load(validFields: fields, from: reloaded) == .init(field: "Name", ascending: false))
        SortPreference.save(field: "Date modified", ascending: false, to: defaults)
        try check("Other sort fields retain their selected direction",
            SortPreference.load(validFields: fields, from: reloaded) == .init(field: "Date modified", ascending: false))
        defaults.set(["field": "Unknown future sort", "ascending": false], forKey: SortPreference.key)
        try check("An unknown saved sort falls back as a complete choice", SortPreference.load(validFields: fields, from: reloaded) == nil)
        defaults.set(["field": "Date added"], forKey: SortPreference.key)
        try check("A partial saved sort does not silently change its direction", SortPreference.load(validFields: fields, from: reloaded) == nil)
        defaults.set(["field": "Name", "ascending": "descending"], forKey: SortPreference.key)
        try check("A malformed sort direction falls back safely", SortPreference.load(validFields: fields, from: reloaded) == nil)
    }

    @MainActor
    static func searchKeyboard() throws {
        // Exercise native responders and input without displaying or activating any window.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = window.contentView!
        let keyboard = GalleryKeyboard()
        let field = RoseSearchTextField(frame: NSRect(x: 330, y: 430, width: 290, height: 22))
        field.keyboard = keyboard
        var query = ""
        var enabled = true
        field.onTextChange = { query = $0 }
        field.isBrowsingEnabled = { enabled }
        content.addSubview(field)
        try check("Startup does not create a search editor or caret", field.currentEditor() == nil)
        try check("An empty library has a browsing responder", window.firstResponder is GalleryBrowsingResponder)

        let items = FixtureItems()
        let collection = RoseCollectionView(frame: NSRect(x: 0, y: 0, width: 440, height: 280))
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 90, height: 100)
        layout.minimumLineSpacing = 10
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsEmptySelection = true
        collection.register(FixtureItem.self, forItemWithIdentifier: FixtureItems.identifier)
        collection.dataSource = items
        var opened = 0
        collection.onOpen = { opened += 1 }
        keyboard.collection = collection
        let scroll = NSScrollView(frame: NSRect(x: 180, y: 20, width: 440, height: 280))
        scroll.hasVerticalScroller = true
        scroll.documentView = collection
        content.addSubview(scroll)
        collection.reloadData()
        scroll.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        try check("The gallery takes browsing focus when attached", window.firstResponder === collection)
        try check("Initial window activation targets the gallery rather than search", window.initialFirstResponder === collection)
        try check("The fixture has enough content to page", collection.bounds.height > scroll.contentSize.height)

        func key(_ code: UInt16 = 49, _ text: String = " ", _ flags: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: text,
                             charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code)!
        }
        func deliver(_ event: NSEvent) {
            if let routed = field.routeSearchEvent(event) { window.firstResponder?.keyDown(with: routed) }
        }
        func click(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                               clickCount: 1, pressure: 1)!
        }
        var focusRequest = 0
        func editSearch() -> NSTextView {
            focusRequest += 1
            field.requestSearchFocus(focusRequest)
            return field.currentEditor() as! NSTextView
        }

        deliver(key())
        try check("Startup Space moves the actual gallery down", scroll.contentView.bounds.minY > 0 && query.isEmpty)
        try check("Paging keeps the search caret absent", field.currentEditor() == nil && window.firstResponder === collection)
        deliver(key(49, " ", [.shift]))
        try check("Shift–Space returns the actual gallery upward", scroll.contentView.bounds.minY == 0)
        deliver(key(repeated: true))
        try check("Held Space continues paging", scroll.contentView.bounds.minY > 0)

        let desktopArrow = key(123, "\u{F702}", [.option])
        try check("Option–Arrow desktop bindings never activate search", field.routeSearchEvent(desktopArrow) === desktopArrow && field.currentEditor() == nil)
        let shortcut = key(8, "c", [.command])
        try check("Command shortcuts keep browsing focus", field.routeSearchEvent(shortcut) === shortcut && field.currentEditor() == nil)
        let arrow = key(125, "\u{F701}")
        try check("Navigation keys do not activate search", field.routeSearchEvent(arrow) === arrow && field.currentEditor() == nil)

        deliver(key(15, "r"))
        try check("Typing from browsing enters the first character exactly once", query == "r" && field.stringValue == "r")
        try check("Typing gives the native search editor real focus", window.firstResponder === field.currentEditor())
        deliver(key())
        try check("A visible search caret means Space inserts text", query == "r ")
        (field.currentEditor() as! NSTextView).insertText("quartz", replacementRange: NSRange(location: NSNotFound, length: 0))
        try check("Multiword queries retain their spaces", query == "r quartz")

        let selected = IndexPath(item: 0, section: 0)
        collection.selectionIndexPaths = [selected]
        deliver(key(53, "\u{1B}"))
        try check("Escape leaves search and removes its caret", field.currentEditor() == nil && window.firstResponder === collection)
        try check("Leaving search keeps its query", query == "r quartz" && field.stringValue == query)
        try check("Leaving search keeps the image selection", collection.selectionIndexPaths == [selected])
        deliver(key())
        try check("Browsing Space still opens a selected image", opened == 1)
        deliver(key(repeated: true))
        try check("Repeated Space does not repeatedly open the viewer", opened == 1)
        collection.selectionIndexPaths = []
        deliver(key(8, "c"))
        try check("Typing from filtered browsing starts a new query", query == "c")
        deliver(key(53, "\u{1B}"))

        deliver(key(16, "y"))
        deliver(key(51, "\u{7F}"))
        try check("Backspace removing the last character leaves search with no caret", query.isEmpty && field.stringValue.isEmpty && field.currentEditor() == nil && window.firstResponder === collection)
        let beforePaging = scroll.contentView.bounds.minY
        deliver(key())
        try check("Space immediately scrolls after deleting the last search character", scroll.contentView.bounds.minY > beforePaging && query.isEmpty)
        deliver(key(16, "y"))
        try check("Typing immediately resumes search after deleting it", query == "y" && window.firstResponder === field.currentEditor())
        deliver(key(0, "a"))
        deliver(key(51, "\u{7F}"))
        try check("Backspace keeps editing while part of the query remains", query == "y" && window.firstResponder === field.currentEditor())
        let deletionEditor = field.currentEditor() as! NSTextView
        deletionEditor.insertText("ellow", replacementRange: NSRange(location: NSNotFound, length: 0))
        deletionEditor.selectAll(nil)
        deliver(key(51, "\u{7F}"))
        try check("Deleting a selected whole query also returns to browsing", query.isEmpty && field.currentEditor() == nil && window.firstResponder === collection)
        _ = editSearch()
        deliver(key(51, "\u{7F}"))
        try check("Backspace in an explicitly focused empty search returns to browsing", field.currentEditor() == nil && window.firstResponder === collection)
        deliver(key(8, "c"))
        deliver(key(53, "\u{1B}"))

        let title = NSTextField(labelWithString: "All images")
        title.frame = NSRect(x: 200, y: 350, width: 200, height: 30)
        content.addSubview(title)
        let areas: [(String, NSPoint)] = [
            ("pink toolbar background", NSPoint(x: 200, y: 415)),
            ("All images heading", NSPoint(x: 230, y: 365)),
            ("sidebar branding", NSPoint(x: 40, y: 440)),
            ("gallery background", NSPoint(x: 200, y: 10))
        ]
        for (name, point) in areas {
            _ = editSearch()
            collection.selectionIndexPaths = [selected]
            let mouse = click(point)
            let routed = field.routeSearchEvent(mouse)
            try check("Clicking \(name) returns focus without swallowing the click", routed === mouse && window.firstResponder === collection && field.currentEditor() == nil)
            try check("Clicking \(name) preserves the query and clears image selection", query == "c" && collection.selectionIndexPaths.isEmpty)
        }
        collection.selectionIndexPaths = []

        _ = editSearch()
        let searchMouse = click(field.convert(NSPoint(x: 40, y: 10), to: nil))
        let activeEditor = field.currentEditor()
        try check("Clicks inside search leave native editing in control", field.routeSearchEvent(searchMouse) === searchMouse && window.firstResponder === activeEditor)
        let editor = editSearch()
        editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        deliver(key())
        try check("Explicit search editing allows leading spaces", query == " ")
        deliver(key(53, "\u{1B}"))
        try check("Escape preserves even a whitespace-only query", field.currentEditor() == nil && query == " ")
        let commandEditor = editSearch()
        try check("Command–F's focus request selects the existing query", window.firstResponder === commandEditor && commandEditor.selectedRange().length == 1)
        commandEditor.setMarkedText("a", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composingEscape = key(53, "\u{1B}")
        try check("Escape first belongs to active input-method composition", commandEditor.hasMarkedText() && field.routeSearchEvent(composingEscape) === composingEscape && window.firstResponder === commandEditor)
        let composingSpace = key()
        try check("Composing text retains native Space behavior", field.routeSearchEvent(composingSpace) === composingSpace)
        let composingBackspace = key(51, "\u{7F}")
        try check("Backspace within input-method composition stays native", field.routeSearchEvent(composingBackspace) === composingBackspace && window.firstResponder === commandEditor)
        commandEditor.unmarkText()

        let notes = NSTextView(frame: NSRect(x: 15, y: 150, width: 140, height: 100))
        content.addSubview(notes)
        let noteMouse = click(notes.convert(NSPoint(x: 10, y: 10), to: nil))
        let beforeNotes = window.firstResponder
        try check("Clicking another text input is not redirected to browsing", field.routeSearchEvent(noteMouse) === noteMouse && window.firstResponder === beforeNotes)
        window.makeFirstResponder(notes)
        let savedQuery = query
        deliver(key(15, "r"))
        deliver(key())
        try check("Notes keep native typing and spaces", notes.string == "r " && query == savedQuery && window.firstResponder === notes)
        _ = field.routeSearchEvent(click(NSPoint(x: 200, y: 415)))
        try check("Clicking background also leaves a note editor", window.firstResponder === collection)

        let otherField = NSTextField(frame: NSRect(x: 15, y: 100, width: 140, height: 24))
        content.addSubview(otherField)
        window.makeFirstResponder(otherField)
        deliver(key())
        try check("Other text fields retain literal Space input", otherField.stringValue == " " && query == savedQuery)

        let action = FixtureButtonAction()
        let button = NSButton(title: "Sidebar action", target: action, action: #selector(FixtureButtonAction.clicked))
        button.frame = NSRect(x: 15, y: 300, width: 140, height: 24)
        content.addSubview(button)
        _ = editSearch()
        let buttonMouse = click(button.convert(NSPoint(x: 40, y: 10), to: nil))
        try check("A control click releases search without consuming the event", field.routeSearchEvent(buttonMouse) === buttonMouse && field.currentEditor() == nil)
        button.performClick(nil)
        try check("The control's normal action still runs", action.clicks == 1)

        _ = editSearch()
        enabled = false
        let suspendedEditor = window.firstResponder
        let suspendedEscape = key(53, "\u{1B}")
        try check("A viewer or modal owns Escape while browsing is suspended", field.routeSearchEvent(suspendedEscape) === suspendedEscape && window.firstResponder === suspendedEditor)
        let suspendedMouse = click(NSPoint(x: 200, y: 415))
        try check("Suspended browsing does not move focus under an overlay", field.routeSearchEvent(suspendedMouse) === suspendedMouse && window.firstResponder === suspendedEditor)
        enabled = true
        deliver(key(53, "\u{1B}"))

        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        let otherKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: otherWindow.windowNumber, context: nil, characters: "r",
                                       charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
        try check("Another window's typing never activates this search", field.routeSearchEvent(otherKey) === otherKey && field.currentEditor() == nil)
        try check("Neither fixture window was displayed", !window.isVisible && !otherWindow.isVisible)
    }
}

@MainActor
final class FixtureItem: NSCollectionViewItem {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 100)) }
}

@MainActor
final class FixtureItems: NSObject, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("FixtureItem")
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 64 }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: Self.identifier, for: indexPath)
    }
}

final class FixtureButtonAction: NSObject {
    var clicks = 0
    @objc func clicked() { clicks += 1 }
}
