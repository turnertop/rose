import SwiftUI
import AppKit
import ImageIO
import RoseCore

enum ViewerZoomCommand { case fit, actual, zoomIn, zoomOut }

struct ViewerView: View {
    @EnvironmentObject private var library: LibraryModel
    let asset: ImageAsset
    @State private var zoomCommand: ViewerZoomCommand = .fit
    @State private var request = 0
    @State private var zoom = 1.0
    @State private var loading = true
    @State private var failed = false
    @State private var keyboardMonitor: Any?
    @State private var wasFullScreen = false
    @State private var viewerWindow = ViewerWindowReference()
    @AppStorage(ViewerScrollZoomPreference.key) private var twoFingerScrollZoom = ViewerScrollZoomPreference.defaultValue

    private var position: String {
        guard let index = library.visibleAssets.firstIndex(where: { $0.id == asset.id }) else { return "" }
        return "\(index + 1) of \(library.visibleAssets.count)"
    }

    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.06, blue: 0.078).ignoresSafeArea()
            ZoomableImageView(asset: asset, command: zoomCommand, request: request, twoFingerScrollZoom: twoFingerScrollZoom,
                              ownerWindow: viewerWindow, copyImage: { library.copyImage(asset) },
                              showInFinder: { library.reveal(asset) }, zoom: $zoom, loading: $loading, failed: $failed)
                .padding(.top, 65).padding(.bottom, 70).padding(.horizontal, 52)
                .onTapGesture(count: 2) { send(zoom < 0.99 ? .actual : .fit) }
            if loading { ProgressView().controlSize(.large) }
            if failed {
                VStack(spacing: 13) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 36, weight: .light))
                    Text("This image couldn’t be opened.").font(.title3)
                    Text("It may have moved, be offline, or use an unsupported format.").font(.callout).foregroundStyle(.secondary)
                    Button("Show in Finder") { library.reveal() }
                }
            }
            VStack {
                HStack(spacing: 15) {
                    GlassIconButton(symbol: "xmark", help: "Close viewer · Esc", action: close)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text("\(asset.dimensions) · \(asset.fileExtension.uppercased()) · \(asset.formattedSize)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(position).font(.system(size: 11)).foregroundStyle(.secondary)
                    GlassIconButton(symbol: asset.annotation.isFavorite ? "star.fill" : "star", help: "Toggle favorite · ⌘ D", active: asset.annotation.isFavorite) { library.toggleFavorite() }
                    GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Toggle full screen · F") { viewerWindow.window?.toggleFullScreen(nil) }
                }.padding(.horizontal, 20).padding(.vertical, 11).background { RoseGlassSurface(tinted: false) }
                Spacer()
                HStack(spacing: 6) {
                    GlassIconButton(symbol: "minus", help: "Zoom out · −") { send(.zoomOut) }
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced)).frame(width: 47)
                    GlassIconButton(symbol: "plus", help: "Zoom in · +") { send(.zoomIn) }
                    Divider().frame(height: 17).padding(.horizontal, 6)
                    Button("Fit") { send(.fit) }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 6).help("Fit to window · 0")
                    Button("Actual size") { send(.actual) }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 6).help("Actual size · 1")
                }.padding(.horizontal, 10).padding(.vertical, 5).roseGlass(radius: 17).padding(.bottom, 19)
            }
            HStack {
                GlassIconButton(symbol: "chevron.left", help: "Previous image · ←") { library.navigate(-1) }.roseGlass(radius: 12)
                Spacer()
                GlassIconButton(symbol: "chevron.right", help: "Next image · →") { library.navigate(1) }.roseGlass(radius: 12)
            }.padding(.horizontal, 14).allowsHitTesting(true)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            wasFullScreen = (viewerWindow.window ?? NSApp.keyWindow)?.styleMask.contains(.fullScreen) == true
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard viewerWindow.owns(event) else { return event }
                guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { return event }
                switch event.keyCode {
                case 53: close()
                case 49: if !event.isARepeat { close() }
                case 123: library.navigate(-1)
                case 124: library.navigate(1)
                case 24, 69: send(.zoomIn)
                case 27, 78: send(.zoomOut)
                case 29, 82: send(.fit)
                case 18, 83: send(.actual)
                case 3: viewerWindow.window?.toggleFullScreen(nil)
                default: return event
                }
                return nil
            }
        }
        .onDisappear {
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
            if !wasFullScreen, viewerWindow.window?.styleMask.contains(.fullScreen) == true { viewerWindow.window?.toggleFullScreen(nil) }
        }
    }

    private func send(_ command: ViewerZoomCommand) { zoomCommand = command; request += 1 }
    private func close() { library.viewerPresented = false }
}

struct ZoomableImageView: NSViewRepresentable {
    let asset: ImageAsset
    let command: ViewerZoomCommand
    let request: Int
    let twoFingerScrollZoom: Bool
    let ownerWindow: ViewerWindowReference
    let copyImage: () -> Void
    let showInFinder: () -> Void
    @Binding var zoom: Double
    @Binding var loading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.twoFingerScrollZoom = twoFingerScrollZoom
        scroll.ownerWindow = ownerWindow
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        let image = PannableImageView()
        image.imageScaling = .scaleAxesIndependently
        image.animates = true
        image.isEditable = false
        image.allowsCutCopyPaste = false
        image.scrollView = scroll
        scroll.documentView = image
        scroll.configureImageActions(copy: copyImage, reveal: showInFinder)
        context.coordinator.scroll = scroll; context.coordinator.imageView = image
        scroll.onUserZoom = { [weak coordinator = context.coordinator] in coordinator?.fitted = false }
        scroll.onResize = { [weak coordinator = context.coordinator] in if coordinator?.fitted == true { coordinator?.fit() } }
        context.coordinator.observation = scroll.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] scroll, _ in
            DispatchQueue.main.async { coordinator?.parent.zoom = scroll.magnification }
        }
        return scroll
    }

    func updateNSView(_ nsView: ZoomScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        nsView.twoFingerScrollZoom = twoFingerScrollZoom
        nsView.configureImageActions(copy: copyImage, reveal: showInFinder)
        let signature = "\(asset.id)|\(asset.modifiedAt.timeIntervalSince1970)"
        if coordinator.signature != signature { coordinator.signature = signature; coordinator.load(asset) }
        if coordinator.lastRequest != request { coordinator.lastRequest = request; coordinator.apply(command) }
    }

    static func dismantleNSView(_ nsView: ZoomScrollView, coordinator: Coordinator) {
        coordinator.operation?.cancel(); coordinator.observation = nil
        nsView.configureImageActions(copy: nil, reveal: nil)
    }

    final class Coordinator {
        var parent: ZoomableImageView
        weak var scroll: ZoomScrollView?
        weak var imageView: PannableImageView?
        var signature = ""
        var lastRequest = -1
        var fitted = true
        var operation: Operation?
        var observation: NSKeyValueObservation?
        private let queue: OperationQueue = {
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated; return queue
        }()

        init(parent: ZoomableImageView) { self.parent = parent }

        func load(_ asset: ImageAsset) {
            operation?.cancel(); fitted = true; imageView?.image = nil
            let expectedSignature = signature
            DispatchQueue.main.async { self.parent.loading = true; self.parent.failed = false }
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let image: NSImage? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                    if CGImageSourceGetCount(source) > 1, asset.fileExtension == "gif" { return NSImage(contentsOf: asset.url) }
                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 8192
                    ] as CFDictionary) else { return nil }
                    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
                guard !operation.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !operation.isCancelled, self.signature == expectedSignature else { return }
                    self.parent.loading = false; self.parent.failed = image == nil
                    self.imageView?.image = image
                    let scale = self.scroll?.window?.backingScaleFactor ?? 2
                    self.imageView?.setFrameSize(NSSize(width: CGFloat(asset.width) / scale, height: CGFloat(asset.height) / scale))
                    self.fit()
                }
            }
            self.operation = operation
            queue.addOperation(operation)
        }

        func fit() {
            guard let scroll, let imageView, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
            let available = scroll.contentSize
            let magnification = min(available.width / imageView.frame.width, available.height / imageView.frame.height)
            scroll.setMagnification(max(0.01, min(magnification, 8)), centeredAt: NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY))
            scroll.contentView.needsLayout = true
        }

        func apply(_ command: ViewerZoomCommand) {
            guard let scroll else { return }
            switch command {
            case .fit: fitted = true; fit()
            case .actual: fitted = false; scroll.setMagnification(1, centeredAt: scroll.contentView.bounds.center)
            case .zoomIn: fitted = false; scroll.setMagnification(min(16, scroll.magnification * 1.25), centeredAt: scroll.contentView.bounds.center)
            case .zoomOut: fitted = false; scroll.setMagnification(max(0.01, scroll.magnification / 1.25), centeredAt: scroll.contentView.bounds.center)
            }
        }
    }
}

private extension NSRect { var center: NSPoint { NSPoint(x: midX, y: midY) } }
