import SwiftUI
import AppKit
import RoseCore
import RoseImaging

@MainActor
struct ImageGridView: NSViewRepresentable {
    @ObservedObject var library: LibraryModel
    let keyboard: GalleryKeyboard

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 13
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 10, right: 4)
        context.coordinator.flowLayout = layout
        let collection = RoseCollectionView()
        collection.collectionViewLayout = library.displayMode == .fit ? context.coordinator.fitLayout : layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.register(RoseImageItem.self, forItemWithIdentifier: RoseImageItem.identifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.onOpen = { [weak library] in library?.viewerPresented = true }
        collection.onClearSelection = { [weak library] in library?.select([], primary: nil) }
        collection.onCopy = { [weak library] in
            guard let library else { return }
            let urls = library.visibleAssets.filter { library.selection.contains($0.id) }.map { $0.url as NSURL }
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls)
        }
        collection.menuProvider = { [weak coordinator = context.coordinator] index in coordinator?.menu(at: index) }
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(doubleClick)

        let scroll = RoseGridScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = collection
        scroll.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateLayout(); coordinator?.scheduleViewportUpdate()
        }
        context.coordinator.collection = collection
        keyboard.collection = collection
        keyboard.onClearSelection = collection.onClearSelection
        context.coordinator.scroll = scroll
        context.coordinator.observeViewport()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.library = library
        coordinator.isApplying = true
        let changed = coordinator.assets != library.visibleAssets
        let modeChanged = coordinator.displayMode != library.displayMode
        let oldOrigin = nsView.contentView.bounds.origin
        let anchor = coordinator.scrollAnchor()
        coordinator.displayMode = library.displayMode
        coordinator.targetSize = CGFloat(library.thumbnailSize)
        if changed {
            coordinator.cancelPrefetch()
            coordinator.assets = library.visibleAssets
            coordinator.fitLayout.setAspectRatios(coordinator.assets.map { $0.height > 0 ? Double($0.width) / Double($0.height) : 1 })
            coordinator.collection?.reloadData()
        }
        coordinator.updateLayout()
        let desiredLayout: NSCollectionViewLayout = library.displayMode == .fit ? coordinator.fitLayout : coordinator.flowLayout
        if coordinator.collection?.collectionViewLayout !== desiredLayout {
            coordinator.collection?.collectionViewLayout = desiredLayout
        }
        if modeChanged {
            for case let item as RoseImageItem in coordinator.collection?.visibleItems() ?? [] {
                item.setDisplayMode(library.displayMode)
            }
        }
        let paths = Set(coordinator.assets.enumerated().compactMap { library.selection.contains($0.element.id) ? IndexPath(item: $0.offset, section: 0) : nil })
        if coordinator.collection?.selectionIndexPaths != paths { coordinator.collection?.selectionIndexPaths = paths }
        if changed || modeChanged {
            nsView.layoutSubtreeIfNeeded()
            let restoredY = modeChanged ? coordinator.origin(for: anchor) ?? oldOrigin.y : oldOrigin.y
            nsView.contentView.scroll(to: NSPoint(x: 0, y: min(restoredY, max(0, (nsView.documentView?.bounds.height ?? 0) - nsView.contentSize.height))))
            nsView.reflectScrolledClipView(nsView.contentView)
        }
        if library.primaryID != coordinator.lastPrimaryID {
            coordinator.lastPrimaryID = library.primaryID
            if let id = library.primaryID, let index = coordinator.assets.firstIndex(where: { $0.id == id }) {
                let path = IndexPath(item: index, section: 0)
                if let frame = coordinator.collection?.collectionViewLayout?.layoutAttributesForItem(at: path)?.frame,
                   !nsView.documentVisibleRect.contains(frame) {
                    coordinator.collection?.scrollToItems(at: [path], scrollPosition: .nearestVerticalEdge)
                }
            }
        }
        coordinator.isApplying = false
        coordinator.scheduleViewportUpdate()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var library: LibraryModel
        weak var collection: RoseCollectionView?
        weak var scroll: NSScrollView?
        var flowLayout = NSCollectionViewFlowLayout()
        let fitLayout = JustifiedCollectionLayout()
        var assets: [ImageAsset] = []
        var displayMode: LibraryDisplayMode = .fill
        var targetSize: CGFloat = 190
        var isApplying = false
        var lastPrimaryID: String?
        private let scrollingClient = UUID()
        private var viewportWork: DispatchWorkItem?
        private var settlingWork: DispatchWorkItem?
        private var previousScroll: (y: CGFloat, time: Double)?
        private var rapidScrolling = false
        private var prefetch: [String: ThumbnailRequest] = [:]
        private var diagnostics: ScrollDiagnostics?

        init(library: LibraryModel) { self.library = library }

        deinit {
            NotificationCenter.default.removeObserver(self)
            viewportWork?.cancel(); settlingWork?.cancel()
            prefetch.values.forEach { $0.cancel() }
            ThumbnailService.shared.setRapidScrolling(false, client: scrollingClient)
        }

        func observeViewport() {
            guard let scroll else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(scrollSettled), name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            if ScrollDiagnostics.enabled { diagnostics = ScrollDiagnostics() }
        }

        @objc private func viewportChanged() {
            guard let scroll else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let y = scroll.contentView.bounds.minY
            if let previousScroll {
                let velocity = abs(y - previousScroll.y) / max(0.008, now - previousScroll.time)
                if !rapidScrolling && velocity > max(1200, scroll.contentSize.height * 2.5) {
                    rapidScrolling = true
                    ThumbnailService.shared.setRapidScrolling(true, client: scrollingClient)
                    cancelPrefetch()
                }
            }
            previousScroll = (y, now)
            if let collection { diagnostics?.recordScroll(in: collection) }
            settlingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.scrollSettled() }
            settlingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: work)
            scheduleViewportUpdate()
        }

        @objc private func scrollSettled() {
            settlingWork?.cancel(); settlingWork = nil
            rapidScrolling = false
            ThumbnailService.shared.setRapidScrolling(false, client: scrollingClient)
            scheduleViewportUpdate()
        }

        func scheduleViewportUpdate() {
            guard viewportWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.viewportWork = nil; self.updateViewport()
            }
            viewportWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
        }

        func cancelPrefetch() { prefetch.values.forEach { $0.cancel() }; prefetch.removeAll() }

        private func updateViewport() {
            guard let collection, let layout = collection.collectionViewLayout, let scroll else { return }
            let visible = scroll.documentVisibleRect
            for case let item as RoseImageItem in collection.visibleItems() {
                item.setVisible(!library.viewerPresented && item.view.frame.intersects(visible))
            }
            guard !library.viewerPresented, !rapidScrolling, !visible.isEmpty else { cancelPrefetch(); return }
            let scale = collection.window?.backingScaleFactor ?? 2
            let nearby = visible.insetBy(dx: 0, dy: visible.height * 0.6)
            let attributes = layout.layoutAttributesForElements(in: nearby)
                .filter {
                    guard let index = $0.indexPath?.item else { return false }
                    return !$0.frame.intersects(visible) && assets.indices.contains(index)
                }
                .sorted { abs($0.frame.midY - visible.midY) < abs($1.frame.midY - visible.midY) }.prefix(24)
            var wanted: [(key: String, asset: ImageAsset, pixels: Int)] = []
            for attribute in attributes {
                guard let index = attribute.indexPath?.item else { continue }
                let asset = assets[index]
                let size = displayMode == .list ? CGSize(width: 56, height: 56)
                    : CGSize(width: max(1, attribute.frame.width - 8), height: max(1, attribute.frame.height - 35))
                let pixels = ThumbnailSize.pixels(width: size.width, height: size.height, scale: scale)
                wanted.append(("\(asset.id)|\(pixels)", asset, pixels))
            }
            let wantedKeys = Set(wanted.map(\.key))
            for key in Array(prefetch.keys) where !wantedKeys.contains(key) { prefetch.removeValue(forKey: key)?.cancel() }
            for value in wanted where prefetch[value.key] == nil {
                prefetch[value.key] = ThumbnailService.shared.load(value.asset, maxPixel: value.pixels, priority: .prefetch)
            }
        }

        func scrollAnchor() -> (id: String, fraction: CGFloat)? {
            guard let collection, let scroll else { return nil }
            let rect = scroll.documentVisibleRect
            let candidates = collection.indexPathsForVisibleItems().sorted()
            for path in candidates where assets.indices.contains(path.item) {
                if let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: path)?.frame, frame.maxY > rect.minY {
                    return (assets[path.item].id, max(0, min(1, (rect.minY - frame.minY) / max(1, frame.height))))
                }
            }
            return nil
        }

        func origin(for anchor: (id: String, fraction: CGFloat)?) -> CGFloat? {
            guard let anchor, let index = assets.firstIndex(where: { $0.id == anchor.id }),
                  let frame = collection?.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return nil }
            return max(0, frame.minY + anchor.fraction * frame.height)
        }

        func updateLayout() {
            guard let scroll else { return }
            if displayMode == .fit {
                fitLayout.configure(width: max(100, scroll.contentSize.width), targetHeight: targetSize * 1.12)
                return
            }
            let available = max(100, scroll.contentSize.width - 8)
            let size: NSSize
            if displayMode == .list { size = NSSize(width: available, height: 69) }
            else {
                let columns = max(1, floor((available + 10) / (targetSize + 10)))
                let width = floor((available - (columns - 1) * 10) / columns)
                size = NSSize(width: width, height: width * 1.12 + 33)
            }
            if flowLayout.itemSize != size { flowLayout.itemSize = size; flowLayout.invalidateLayout() }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { assets.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: RoseImageItem.identifier, for: indexPath) as! RoseImageItem
            item.configure(asset: assets[indexPath.item], mode: displayMode)
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
            // A previously prepared offscreen cell must adopt the latest mode too.
            (item as? RoseImageItem)?.setDisplayMode(displayMode)
            (item as? RoseImageItem)?.setVisible(!library.viewerPresented && item.view.frame.intersects(scroll?.documentVisibleRect ?? .zero))
        }

        func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
            (item as? RoseImageItem)?.setVisible(false)
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplying else { return }
            let primary = indexPaths.sorted().last.flatMap { assets.indices.contains($0.item) ? assets[$0.item].id : nil }
            syncSelection(primary: primary)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplying else { return }
            syncSelection(primary: library.primaryID)
        }

        private func syncSelection(primary: String?) {
            let ids = Set((collection?.selectionIndexPaths ?? []).compactMap { assets.indices.contains($0.item) ? assets[$0.item].id : nil })
            library.select(ids, primary: primary)
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            assets[indexPath.item].url as NSURL
        }

        @objc func doubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let collection, let path = collection.indexPathForItem(at: recognizer.location(in: collection)), assets.indices.contains(path.item) else { return }
            let id = assets[path.item].id
            library.select([id], primary: id)
            library.viewerPresented = true
        }

        func menu(at index: IndexPath?) -> NSMenu? {
            guard let index, assets.indices.contains(index.item) else { return nil }
            let asset = assets[index.item]
            if !library.selection.contains(asset.id) {
                collection?.selectionIndexPaths = [index]
                library.select([asset.id], primary: asset.id)
            } else { library.select(library.selection, primary: asset.id) }
            let menu = NSMenu()
            menu.addItem(.action("Open in Viewer", symbol: "arrow.up.left.and.arrow.down.right") { [weak library] in library?.viewerPresented = true })
            menu.addItem(.action(asset.annotation.isFavorite ? "Remove from Favorites" : "Add to Favorites", symbol: "star") { [weak library] in library?.toggleFavorite(asset) })
            menu.addItem(.separator())
            menu.addItem(.action("Show in Finder", symbol: "folder") { [weak library] in library?.reveal(asset) })
            menu.addItem(.action("Open in Default App", symbol: "arrow.up.forward.app") { NSWorkspace.shared.open(asset.url) })
            menu.addItem(.action("Copy Image", symbol: "doc.on.doc") { [weak library] in library?.copyImage(asset) })
            menu.addItem(.action("Copy File Path", symbol: "link") { [weak library] in library?.copyPath(asset) })
            let addMenu = NSMenu(title: "Add to Collection")
            for collection in library.collections {
                let paths = library.selection
                addMenu.addItem(.action(collection.name, symbol: "square.stack") { [weak library] in library?.addToCollection(collection.id, paths: paths) })
            }
            addMenu.addItem(.action("New Collection…", symbol: "plus") { [weak library] in library?.collectionSheet = true })
            let addItem = NSMenuItem(title: "Add to Collection", action: nil, keyEquivalent: "")
            addItem.submenu = addMenu; menu.addItem(addItem)
            if case .collection = library.location {
                let paths = library.selection
                menu.addItem(.action("Remove from Collection", symbol: "minus.circle") { [weak library] in library?.removeFromCollection(paths: paths) })
            }
            menu.addItem(.separator())
            menu.addItem(.action("Move to Trash…", symbol: "trash") { [weak library] in library?.trash(asset) })
            return menu
        }
    }
}

@MainActor
final class RoseGridScrollView: NSScrollView {
    var onLayout: (@MainActor () -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

final class RoseImageItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("RoseImageItem")
    private var operation: ThumbnailRequest?
    private var asset: ImageAsset?
    private var visible = false
    private var requestedPixels = 0
    private var loadedPixels = 0
    private var requestID = UUID()
    private var tile: RoseTileView { view as! RoseTileView }

    override func loadView() {
        let tile = RoseTileView()
        tile.onImageAreaChange = { [weak self] in self?.loadForCurrentSize() }
        view = tile
    }
    override var isSelected: Bool { didSet { if isViewLoaded { tile.selected = isSelected } } }

    func configure(asset: ImageAsset, mode: LibraryDisplayMode) {
        operation?.cancel()
        self.asset = asset
        requestID = UUID(); requestedPixels = 0; loadedPixels = 0
        setDisplayMode(mode)
        tile.nameLabel.stringValue = asset.name
        tile.detailLabel.stringValue = "\(asset.dimensions)  ·  \(asset.fileExtension.uppercased())  ·  \(asset.formattedSize)"
        tile.favorite.isHidden = !asset.annotation.isFavorite
        tile.canvas.image = nil; tile.canvas.failed = false
        tile.selected = isSelected
        tile.toolTip = "\(asset.name)\n\(asset.dimensions) · \(asset.formattedSize)"
        tile.setAccessibilityLabel(asset.name)
        tile.setAccessibilityRole(.image)
        tile.needsLayout = true
        if visible { loadForCurrentSize() }
    }

    func setVisible(_ value: Bool) {
        visible = value
        if value { view.layoutSubtreeIfNeeded(); loadForCurrentSize() }
        else { operation?.cancel(); operation = nil; requestedPixels = 0 }
    }

    private func loadForCurrentSize() {
        guard visible, let asset, tile.canvas.bounds.width > 0, tile.canvas.bounds.height > 0 else { return }
        let size = tile.canvas.bounds.size
        let pixels = ThumbnailSize.pixels(width: size.width, height: size.height, scale: view.window?.backingScaleFactor ?? 2)
        guard !(requestedPixels == pixels && operation != nil),
              !(loadedPixels == pixels && (tile.canvas.image != nil || tile.canvas.failed)) else { return }
        operation?.cancel()
        requestedPixels = pixels
        let expected = UUID(); requestID = expected
        operation = ThumbnailService.shared.load(asset, maxPixel: pixels) { [weak self] image in
            guard let self, self.requestID == expected else { return }
            self.operation = nil; self.loadedPixels = pixels
            self.tile.canvas.image = image; self.tile.canvas.failed = image == nil
        }
    }

    func setDisplayMode(_ mode: LibraryDisplayMode) {
        let list = mode == .list
        if tile.listMode != list { tile.listMode = list }
        tile.canvas.fitImage = mode == .fit
    }

    override func prepareForReuse() {
        super.prepareForReuse(); operation?.cancel(); operation = nil; asset = nil; visible = false
        requestID = UUID(); requestedPixels = 0; loadedPixels = 0; tile.canvas.image = nil
    }
    deinit { operation?.cancel() }
}

final class RoseTileView: NSView {
    let canvas = ThumbnailImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let favorite = NSImageView()
    private let selectionOutline = NSView()
    var onImageAreaChange: (() -> Void)?
    var listMode = false { didSet { needsLayout = true; updateAppearance() } }
    var selected = false { didSet { updateAppearance() } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 14
        canvas.layer?.masksToBounds = true
        selectionOutline.wantsLayer = true
        selectionOutline.layer?.cornerRadius = 17
        selectionOutline.layer?.borderWidth = 2
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = .labelColor
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        favorite.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")
        favorite.contentTintColor = .white
        favorite.imageScaling = .scaleProportionallyDown
        favorite.wantsLayer = true
        favorite.layer?.backgroundColor = RoseStyle.nsAccent.withAlphaComponent(0.85).cgColor
        favorite.layer?.cornerRadius = 10
        addSubview(selectionOutline); addSubview(canvas); addSubview(nameLabel); addSubview(detailLabel); addSubview(favorite)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        if listMode {
            canvas.frame = NSRect(x: 7, y: 6, width: 56, height: 56)
            canvas.layer?.cornerRadius = 9
            nameLabel.frame = NSRect(x: 76, y: 13, width: max(1, bounds.width - 112), height: 18)
            detailLabel.frame = NSRect(x: 76, y: 37, width: max(1, bounds.width - 112), height: 16)
            detailLabel.isHidden = false
            favorite.frame = NSRect(x: bounds.width - 29, y: 23, width: 21, height: 21)
            selectionOutline.frame = bounds.insetBy(dx: 1, dy: 1)
            selectionOutline.layer?.cornerRadius = 13
        } else {
            canvas.frame = NSRect(x: 4, y: 4, width: bounds.width - 8, height: bounds.height - 35)
            canvas.layer?.cornerRadius = 14
            nameLabel.frame = NSRect(x: 6, y: bounds.height - 24, width: bounds.width - 12, height: 16)
            detailLabel.isHidden = true
            favorite.frame = NSRect(x: bounds.width - 32, y: 12, width: 21, height: 21)
            selectionOutline.frame = canvas.frame.insetBy(dx: -3, dy: -3)
            selectionOutline.layer?.cornerRadius = 17
        }
        onImageAreaChange?()
    }

    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); onImageAreaChange?() }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }

    private func updateAppearance() {
        selectionOutline.layer?.borderColor = (selected ? RoseStyle.nsAccent : .clear).cgColor
        selectionOutline.layer?.backgroundColor = selected ? RoseStyle.nsAccent.withAlphaComponent(0.06).cgColor : nil
        nameLabel.textColor = selected ? RoseStyle.nsAccent : .labelColor
        needsDisplay = true
    }
}

final class ThumbnailImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var failed = false { didSet { needsDisplay = true } }
    var fitImage = false { didSet { if fitImage != oldValue { needsDisplay = true } } }
    override var wantsUpdateLayer: Bool { true }
    private let placeholder = NSImageView()
    private static let waiting = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    private static let unavailable = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        placeholder.imageScaling = .scaleProportionallyDown
        placeholder.alphaValue = 0.16
        addSubview(placeholder)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let size = min(24, bounds.width * 0.3)
        placeholder.frame = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
    }
    override func updateLayer() {
        // Prepared bitmaps go straight to Core Animation: no NSImage.draw/decode/resize here.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor
        layer?.contents = image
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        layer?.contentsGravity = fitImage ? .resizeAspect : .resizeAspectFill
        placeholder.isHidden = image != nil
        placeholder.image = failed ? Self.unavailable : Self.waiting
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
private final class MenuAction: NSObject {
    let perform: @MainActor () -> Void
    init(_ perform: @escaping @MainActor () -> Void) { self.perform = perform }
    @objc func run(_ sender: Any?) { perform() }
}

extension NSMenuItem {
    @MainActor
    static func action(_ title: String, symbol: String, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let action = MenuAction(perform)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
        item.target = action; item.representedObject = action
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}
