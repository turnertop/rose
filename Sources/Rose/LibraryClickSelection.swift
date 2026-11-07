import AppKit
import SwiftUI

/// SwiftUI controls can share one hosting view, so mark their geometry explicitly.
final class LibrarySelectionClickTargets {
    private final class WeakRegion {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }
    private var regions: [ObjectIdentifier: WeakRegion] = [:]

    @MainActor func register(_ view: NSView) { regions[ObjectIdentifier(view)] = WeakRegion(view) }
    @MainActor func unregister(_ view: NSView) { regions.removeValue(forKey: ObjectIdentifier(view)) }

    @MainActor func preservesSelection(at event: NSEvent) -> Bool {
        regions = regions.filter { $0.value.view != nil }
        return regions.values.contains { region in
            guard let view = region.view, view.window === event.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point), view.visibleRect.contains(point) else { return false }
            var ancestor = view.superview
            while let parent = ancestor {
                if parent is NSClipView, !parent.bounds.contains(parent.convert(event.locationInWindow, from: nil)) { return false }
                ancestor = parent.superview
            }
            return true
        }
    }
}

final class SelectionProtectionView: NSView {
    weak var targets: LibrarySelectionClickTargets? {
        didSet {
            guard targets !== oldValue else { return }
            oldValue?.unregister(self)
            if window != nil { targets?.register(self) }
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { targets?.unregister(self) }
        else { targets?.register(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct SelectionProtectionRegion: NSViewRepresentable {
    let targets: LibrarySelectionClickTargets
    func makeNSView(context: Context) -> SelectionProtectionView {
        let view = SelectionProtectionView(frame: .zero)
        view.setAccessibilityElement(false)
        view.targets = targets
        return view
    }
    func updateNSView(_ view: SelectionProtectionView, context: Context) { view.targets = targets }
    static func dismantleNSView(_ view: SelectionProtectionView, coordinator: ()) { view.targets = nil }
}

extension View {
    func preservesImageSelection(using keyboard: GalleryKeyboard) -> some View {
        background {
            GeometryReader { geometry in
                SelectionProtectionRegion(targets: keyboard.selectionClickTargets)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }.allowsHitTesting(false)
        }
    }
}
