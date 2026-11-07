import AppKit
import SwiftUI

@MainActor
struct LibrarySearchField: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    let keyboard: GalleryKeyboard
    var isBrowsingEnabled: @MainActor () -> Bool

    func makeNSView(context: Context) -> RoseSearchTextField {
        let field = RoseSearchTextField(frame: .zero)
        field.placeholderString = "Search this view"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Search images")
        update(field)
        return field
    }

    func updateNSView(_ field: RoseSearchTextField, context: Context) { update(field) }

    private func update(_ field: RoseSearchTextField) {
        field.onTextChange = { text = $0 }
        field.keyboard = keyboard
        field.isBrowsingEnabled = isBrowsingEnabled
        if field.stringValue != text { field.stringValue = text }
        field.requestSearchFocus(focusRequest)
        field.refreshBrowsingFocus()
    }
}

/// The caret exists only while editing. Browsing keystrokes activate native search on demand.
@MainActor
final class RoseSearchTextField: NSTextField, NSTextFieldDelegate {
    var onTextChange: (@MainActor (String) -> Void)?
    var keyboard = GalleryKeyboard()
    var isBrowsingEnabled: @MainActor () -> Bool = { true }
    private var lastFocusRequest = 0
    private var pendingSearchFocus = false
    private var configuredInitialFocus = false
    private var keyboardMonitor: Any?
    private lazy var browseResponder: RoseBrowseResponderView = {
        let view = RoseBrowseResponderView(frame: .zero)
        view.searchField = self
        view.setAccessibilityElement(false)
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
        addSubview(browseResponder)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        guard let window else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.routeSearchEvent(event)
        }
        if !configuredInitialFocus {
            configuredInitialFocus = true
            window.initialFirstResponder = browseResponder
            focusBrowsing()
        }
        applyPendingSearchFocus()
    }

    func requestSearchFocus(_ request: Int) {
        guard request != lastFocusRequest else { return }
        lastFocusRequest = request
        pendingSearchFocus = true
        applyPendingSearchFocus()
    }

    private func applyPendingSearchFocus() {
        guard pendingSearchFocus, window != nil else { return }
        pendingSearchFocus = false
        _ = beginSearch(selectAll: true)
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(stringValue)
    }

    @discardableResult
    func focusBrowsing() -> Bool {
        guard let window else { return false }
        return keyboard.focus(in: window) || window.makeFirstResponder(browseResponder)
    }

    func refreshBrowsingFocus() {
        if let window, window.firstResponder === browseResponder { _ = keyboard.focus(in: window) }
    }

    func beginSearch(selectAll: Bool) -> NSTextView? {
        guard canUseLibraryKeyboard, let window, window.makeFirstResponder(self),
              let editor = currentEditor() as? NSTextView else { return nil }
        if selectAll { editor.selectAll(nil) }
        return editor
    }

    private var canUseLibraryKeyboard: Bool {
        guard let window, isBrowsingEnabled(), window.attachedSheet == nil else { return false }
        return NSApp.modalWindow == nil || NSApp.modalWindow === window
    }

    func routeSearchEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, canUseLibraryKeyboard else { return event }
        if event.type == .leftMouseDown {
            if let content = window.contentView,
               let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
               !isTextInput(hit) {
                focusBrowsing()
                keyboard.deselectOnBlankClick(event, hit: hit)
            }
            return event
        }
        guard event.type == .keyDown else { return event }
        if let editor = currentEditor() as? NSTextView, window.firstResponder === editor {
            if event.keyCode == 53, !editor.hasMarkedText(),
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return focusBrowsing() ? nil : event
            }
            if event.keyCode == 51, !editor.hasMarkedText() {
                // Complete native deletion before changing focus, outside the text-change callback.
                if !editor.string.isEmpty { editor.keyDown(with: event) }
                if window.firstResponder === editor, editor.string.isEmpty, !editor.hasMarkedText() {
                    focusBrowsing()
                }
                return nil
            }
            return event
        }
        guard window.firstResponder === browseResponder || keyboard.isFocused(in: window),
              startsSearch(event), let editor = beginSearch(selectAll: true) else { return event }
        // Forward the original key through AppKit's input system, preserving the first character,
        // keyboard layout, dead keys, and input-method composition.
        editor.keyDown(with: event)
        return nil
    }

    private func startsSearch(_ event: NSEvent) -> Bool {
        guard event.keyCode != 49,
              event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
        let characters = event.characters.flatMap { $0.isEmpty ? nil : $0 } ?? event.charactersIgnoringModifiers ?? ""
        return characters.unicodeScalars.contains {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                && !(0xF700...0xF8FF).contains($0.value)
        }
    }

    private func isTextInput(_ hit: NSView) -> Bool {
        var candidate: NSView? = hit
        while let view = candidate {
            if let text = view as? NSTextView, text.isEditable || text.isSelectable { return true }
            if let field = view as? NSTextField, field.isEditable { return true }
            if let scroll = view as? NSScrollView, let text = scroll.documentView as? NSTextView,
               text.isEditable || text.isSelectable { return true }
            candidate = view.superview
        }
        return false
    }
}

@MainActor
private final class RoseBrowseResponderView: NSView, GalleryBrowsingResponder {
    weak var searchField: RoseSearchTextField?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let searchField else { return }
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            _ = searchField.beginSearch(selectAll: true)
            return
        }
        if let window, searchField.keyboard.forward(event, in: window) { return }
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return }
        super.keyDown(with: event)
    }
}
