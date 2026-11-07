import SwiftUI
import RoseCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var dropTargeted = false
    @State private var collectionName = ""
    @State private var sidebarWidth: CGFloat = 240
    @State private var inspectorWidth: CGFloat = 340
    @State private var searchFocusRequest = 0
    @State private var galleryKeyboard = GalleryKeyboard()
    @AppStorage("rose.staticSurfaces") private var staticSurfaces = RoseStyle.defaultStaticSurfaces
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var useStaticSurfaces: Bool { staticSurfaces || reduceTransparency }

    var body: some View {
        ZStack {
            RoseBackground()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if library.showSidebar {
                        SidebarView(keyboard: galleryKeyboard).frame(width: sidebarWidth)
                        PanelResizeHandle(width: $sidebarWidth, range: 205...310, direction: 1, label: "Sidebar width")
                            .preservesImageSelection(using: galleryKeyboard)
                    }
                    VStack(spacing: 0) {
                        toolbar.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 17)
                        HStack(spacing: 0) {
                            gridPane.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                            if library.showInspector {
                                PanelResizeHandle(width: $inspectorWidth, range: 285...460, direction: -1, label: "Inspector width").padding(.horizontal, 3)
                                    .preservesImageSelection(using: galleryKeyboard)
                                InspectorView().frame(width: min(inspectorWidth, max(285, geometry.size.width - (library.showSidebar ? sidebarWidth : 0) - 388)), alignment: .top)
                                    .preservesImageSelection(using: galleryKeyboard)
                            }
                        }.padding(.horizontal, 12).padding(.bottom, 12)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(library.viewerPresented)
            .allowsHitTesting(!library.viewerPresented)
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20).fill(RoseStyle.accent.opacity(0.08))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(RoseStyle.accent, style: StrokeStyle(lineWidth: 2, dash: [8])) }
                    .padding(10).allowsHitTesting(false)
            }
            if library.viewerPresented, let asset = library.selectedAsset {
                ViewerView(asset: asset).transition(.opacity).zIndex(10)
            }
        }
        .frame(minWidth: 1060, minHeight: 680)
        .background(WindowAccessor())
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: library.acceptDrop)
        .alert("Rose needs a moment", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .sheet(isPresented: $library.collectionSheet) { collectionDialog }
        .background {
            Button("") { searchFocusRequest += 1 }.keyboardShortcut("f").hidden()
        }
        .environment(\.roseStaticSurfaces, useStaticSurfaces)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "sidebar.left", help: library.showSidebar ? "Hide sidebar" : "Show sidebar", active: library.showSidebar) {
                library.toggleSidebar()
            }.preservesImageSelection(using: galleryKeyboard)
            Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(RoseStyle.accent.opacity(0.8))
            Text(library.breadcrumb).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                LibrarySearchField(text: $library.search, focusRequest: searchFocusRequest, keyboard: galleryKeyboard) {
                    !library.viewerPresented && !library.collectionSheet && library.errorMessage == nil
                }
                if !library.search.isEmpty {
                    Button { library.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }
            .font(.system(size: 12)).padding(.horizontal, 12).frame(width: 225, height: 34).roseGlass(radius: 12)
            .preservesImageSelection(using: galleryKeyboard)
            GlassIconButton(symbol: "sidebar.right", help: library.showInspector ? "Hide inspector" : "Show inspector", active: library.showInspector) {
                library.toggleInspector()
            }.preservesImageSelection(using: galleryKeyboard)
            Menu {
                Button("Open Folder…", action: library.chooseFolder)
                Button("Refresh Library") { library.refresh() }
                Divider()
                Toggle("Include subfolders", isOn: $library.recursive)
                Toggle("Show sidebar", isOn: $library.showSidebar)
                Toggle("Show inspector", isOn: $library.showInspector)
                Divider()
                Toggle("Static surfaces", isOn: $staticSurfaces)
                Divider()
                SettingsLink { Text("Settings…") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 30, height: 32)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Library options")
                .preservesImageSelection(using: galleryKeyboard)
        }
        .frame(height: 36)
    }

    private var gridPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(library.title).font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-0.7).lineLimit(1)
                    HStack(spacing: 6) {
                        if library.isScanning { ProgressView().controlSize(.mini) }
                        Text(library.isScanning ? "Finding your images\(library.scanCount > 0 ? " · \(library.scanCount)" : "")" : "\(library.visibleAssets.count.formatted()) image\(library.visibleAssets.count == 1 ? "" : "s")")
                        if case .folder = library.location, library.recursive, !library.isScanning { Text("· including subfolders").foregroundStyle(.tertiary) }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(LibraryDisplayMode.allCases) { mode in
                        DisplayModeButton(mode: mode, active: library.displayMode == mode) { library.displayMode = mode }
                    }
                }.padding(3).roseGlass(radius: 14)
                    .preservesImageSelection(using: galleryKeyboard)
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)

            if !library.assets.isEmpty {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Sort by", selection: $library.sort) { ForEach(AssetSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Divider()
                        Toggle("Ascending", isOn: $library.ascending)
                    } label: {
                        Label(library.sort.rawValue, systemImage: library.ascending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }.menuStyle(.borderlessButton).fixedSize()
                        .help(library.sort == .added ? "Date added: newest first when selected. Existing files use the best available local date." : "Sort images")
                        .preservesImageSelection(using: galleryKeyboard)
                    Spacer()
                    if library.displayMode != .list {
                        HStack(spacing: 10) {
                            Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(.secondary)
                            Slider(value: $library.thumbnailSize, in: ThumbnailSizePreference.range).controlSize(.mini).frame(width: 100)
                                .accessibilityLabel(library.displayMode == .fit ? "Fit row height" : "Thumbnail size")
                            Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.secondary)
                        }.preservesImageSelection(using: galleryKeyboard)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 14)
            }

            if library.roots.isEmpty { welcome }
            else if library.selectedFolderUnavailable { missingFolder }
            else if library.visibleAssets.isEmpty && !library.isScanning { emptyResults }
            else {
                ImageGridView(library: library, keyboard: galleryKeyboard).padding(.horizontal, 13)
            }

            HStack(spacing: 8) {
                Circle().fill(library.isScanning ? Color.orange : Color(red: 0.43, green: 0.65, blue: 0.5)).frame(width: 5, height: 5)
                Text(library.statusMessage ?? (library.isScanning ? "Updating from your folders" : "\(library.selection.count > 1 ? "\(library.selection.count) selected · " : "")Files stay in their folders"))
                Spacer()
                if !library.visibleAssets.isEmpty {
                    Text(library.selection.isEmpty ? "Space to scroll · ⇧ Space to scroll up" : "Space to open · Esc to deselect")
                        .foregroundStyle(.tertiary)
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .roseGlass(radius: 23, tint: 0.018)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(RoseStyle.accent.opacity(0.055)).frame(width: 150, height: 150)
                RoseGlassSurface(radius: 17, material: .thin, tinted: false).frame(width: 69, height: 88).rotationEffect(.degrees(-15)).offset(x: -27, y: 1)
                    .overlay { Image(systemName: "sparkles").foregroundStyle(RoseStyle.accent.opacity(0.7)).offset(x: -32, y: -5) }
                RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [.white.opacity(0.8), RoseStyle.accent.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 79, height: 99).rotationEffect(.degrees(12)).offset(x: 18, y: -4)
                    .overlay { Image(systemName: "photo").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(RoseStyle.accent).offset(x: 18, y: -4) }
            }.padding(.bottom, 25)
            Text("Make room for inspiration.").font(.system(size: 25, weight: .medium, design: .rounded)).tracking(-0.6)
            Text("Open a folder. Find your favorites.\nKeep everything right where it belongs.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 12)
            Button(action: library.chooseFolder) {
                Label("Open a folder", systemImage: "folder.badge.plus").font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 19).padding(.vertical, 12)
            }.buttonStyle(.plain).foregroundStyle(.white)
                .background(LinearGradient(colors: [RoseStyle.accent.opacity(0.85), RoseStyle.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                .shadow(color: RoseStyle.accent.opacity(useStaticSurfaces ? 0 : 0.2), radius: useStaticSurfaces ? 0 : 12, y: useStaticSurfaces ? 0 : 5).padding(.top, 26)
            Text("or drop a folder anywhere").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 14)
            Spacer(); Spacer().frame(height: 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Image(systemName: library.search.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(RoseStyle.accent.opacity(0.6))
            Text(library.search.isEmpty ? emptyTitle : "No images found").font(.title3.weight(.medium))
            Text(library.search.isEmpty ? emptyDescription : "Try another filename, folder, format, or tag.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
            if !library.search.isEmpty { Button("Clear search") { library.search = "" }.buttonStyle(.link) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch library.location {
        case .favorites: return "Keep the ones you love."
        case .recent: return "Your next discovery awaits."
        case .collection: return "A fresh collection."
        default: return "A little room to grow."
        }
    }
    private var emptyDescription: String {
        switch library.location {
        case .favorites: return "Tap the star on any image to find it here."
        case .recent: return "Images you select will appear here."
        case .collection: return "Right-click an image to add it to this collection. Your original files stay in place."
        default: return "Add images to this folder in Finder. Rose will find them automatically."
        }
    }

    private var missingFolder: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 35, weight: .light)).foregroundStyle(.secondary)
            Text("This folder is taking a break.").font(.title3.weight(.medium))
            Text("Reconnect the drive or restore the folder’s location. Your library and annotations are still here.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
            Button("Check again") { library.refresh() }.buttonStyle(.bordered)
            Button("Locate folder…", action: library.chooseFolder).buttonStyle(.link)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collectionDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A new collection").font(.title2.weight(.semibold))
            Text("Gather references without moving or duplicating your images.").font(.callout).foregroundStyle(.secondary)
            TextField("Collection name", text: $collectionName).textFieldStyle(.roundedBorder)
                .onSubmit { createCollection() }
            HStack {
                if !library.selection.isEmpty { Text("\(library.selection.count) selected images will be included").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { library.collectionSheet = false }.keyboardShortcut(.cancelAction)
                Button("Create", action: createCollection).buttonStyle(.borderedProminent)
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
            .onAppear { collectionName = "" }
    }
    private func createCollection() {
        guard !collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        library.createCollection(name: collectionName); library.collectionSheet = false
    }
}
