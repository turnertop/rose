import AppKit

/// Marks the temporary browsing responder used while the gallery is being attached.
protocol GalleryBrowsingResponder: AnyObject {}

final class GalleryKeyboard {
    weak var collection: RoseCollectionView?
    var onClearSelection: (@MainActor () -> Void)?
    let selectionClickTargets = LibrarySelectionClickTargets()

    @MainActor func deselectOnBlankClick(_ event: NSEvent, hit: NSView) {
        guard let window = event.window,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !selectionClickTargets.preservesSelection(at: event), !isNativeControl(hit), !hitsImage(event) else { return }
        if let collection, collection.window === window { collection.clearImageSelection() }
        else { onClearSelection?() }
    }

    @MainActor private func hitsImage(_ event: NSEvent) -> Bool {
        guard let collection, collection.window === event.window,
              let clip = collection.enclosingScrollView?.contentView,
              clip.bounds.contains(clip.convert(event.locationInWindow, from: nil)) else { return false }
        return collection.indexPathForItem(at: collection.convert(event.locationInWindow, from: nil)) != nil
    }

    @MainActor private func isNativeControl(_ hit: NSView) -> Bool {
        var candidate: NSView? = hit
        while let view = candidate {
            if let field = view as? NSTextField {
                if field.isEditable || field.isSelectable { return true }
            } else if view is NSControl, !(view is NSImageView) { return true }
            candidate = view.superview
        }
        return false
    }

    @MainActor func focus(in window: NSWindow) -> Bool {
        guard let collection, collection.window === window else { return false }
        if window.initialFirstResponder is GalleryBrowsingResponder { window.initialFirstResponder = collection }
        return window.makeFirstResponder(collection)
    }

    @MainActor func isFocused(in window: NSWindow) -> Bool {
        guard let collection else { return false }
        return window.firstResponder === collection
    }

    @MainActor func forward(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let collection, collection.window === window else { return false }
        collection.keyDown(with: event)
        return true
    }
}

@MainActor
final class RoseCollectionView: NSCollectionView {
    var onOpen: (@MainActor () -> Void)?
    var onClearSelection: (@MainActor () -> Void)?
    var onCopy: (@MainActor () -> Void)?
    var menuProvider: (@MainActor (IndexPath?) -> NSMenu?)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if window.initialFirstResponder is GalleryBrowsingResponder { window.initialFirstResponder = self }
        if window.firstResponder is GalleryBrowsingResponder { window.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        let navigationModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if event.modifierFlags.intersection(navigationModifiers).isEmpty {
            if event.keyCode == 49 {
                handleSpace(backward: event.modifierFlags.contains(.shift), isRepeat: event.isARepeat)
                return
            }
            if event.keyCode == 53 {
                clearImageSelection()
                return
            }
        }
        if event.keyCode == 36 { if !selectionIndexPaths.isEmpty, !event.isARepeat { onOpen?() }; return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { onCopy?(); return }
        super.keyDown(with: event)
    }

    func handleSpace(backward: Bool, isRepeat: Bool) {
        if selectionIndexPaths.isEmpty { scrollPage(backward: backward) }
        else if !isRepeat { onOpen?() }
    }

    func clearImageSelection() {
        selectionIndexPaths = []
        onClearSelection?()
    }

    private func scrollPage(backward: Bool) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        var proposed = clip.bounds
        let distance = max(1, proposed.height - scroll.verticalPageScroll)
        proposed.origin.y += backward ? -distance : distance
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider?(indexPathForItem(at: point))
    }
}
