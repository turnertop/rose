import SwiftUI
import RoseCore

struct SidebarView: View {
    @EnvironmentObject private var library: LibraryModel
    let keyboard: GalleryKeyboard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoseMark()
                VStack(alignment: .leading, spacing: 0) {
                    Text("rose").font(.system(size: 30, weight: .medium, design: .serif)).tracking(-1)
                    Text("A HOME FOR YOUR IMAGES").font(.system(size: 7, weight: .medium)).tracking(1.35).foregroundStyle(.secondary).padding(.top, 3)
                }
            }.padding(.horizontal, 22).padding(.top, 23).padding(.bottom, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    navRow("All images", icon: "photo.on.rectangle", count: library.assets.count, location: .all)
                    navRow("Favorites", icon: "star", count: library.favoriteCount, location: .favorites)
                    navRow("Recently viewed", icon: "clock", count: library.recentPaths.filter { path in library.assets.contains { $0.id == path } }.count, location: .recent)

                    sectionHeader("Folders", addHelp: "Open a folder", action: library.chooseFolder).padding(.top, 27).padding(.bottom, 8)
                    if library.folders.isEmpty {
                        Text("Your folders, just as they are.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 15).padding(.vertical, 4)
                    }
                    ForEach(library.folders) { folder in FolderTreeRow(folder: folder, depth: 0, keyboard: keyboard) }

                    sectionHeader("Collections", addHelp: "New collection") { library.collectionSheet = true }.padding(.top, 27).padding(.bottom, 8)
                    ForEach(library.collections) { collection in
                        navRow(collection.name, icon: "square.stack", count: library.assets.filter { collection.paths.contains($0.id) }.count, location: .collection(collection.id))
                            .contextMenu { Button("Remove Collection", role: .destructive) { library.removeCollection(collection.id) } }
                    }
                    if library.collections.isEmpty {
                        Button { library.collectionSheet = true } label: {
                            Label("A space for a new idea", systemImage: "plus").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 15).padding(.vertical, 4)
                        }.buttonStyle(.plain).preservesImageSelection(using: keyboard)
                    }

                    if !library.allTags.isEmpty {
                        HStack { SectionCaption(title: "Tags"); Spacer() }.padding(.horizontal, 15).padding(.top, 28).padding(.bottom, 10)
                        ForEach(library.allTags, id: \.name) { tag in
                            navRow(tag.name, icon: "number", count: tag.count, location: .tag(tag.name))
                        }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 20)
            }.scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: 13) {
                Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
                Button(action: library.chooseFolder) {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 15, weight: .light))
                        Text("Open a folder").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("⌘ O").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(.horizontal, 10).padding(.vertical, 11).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(RoseStyle.accent)
                    .preservesImageSelection(using: keyboard)
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive").font(.system(size: 9))
                    Text("Local by nature.").font(.system(size: 10))
                }.foregroundStyle(.tertiary).padding(.leading, 10).padding(.bottom, 6)
            }.padding(.horizontal, 17).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { RoseGlassSurface(tint: 0.06) }
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.35)).frame(width: 1) }
    }

    private func sectionHeader(_ title: String, addHelp: String, action: @escaping () -> Void) -> some View {
        HStack { SectionCaption(title: title); Spacer(); Button(action: action) { Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary) }.buttonStyle(.plain).help(addHelp).preservesImageSelection(using: keyboard) }
            .padding(.horizontal, 15)
    }

    private func navRow(_ title: String, icon: String, count: Int, location: LibraryLocation) -> some View {
        SidebarButton(title: title, symbol: icon, count: count, selected: library.location == location) { library.location = location }
            .preservesImageSelection(using: keyboard)
    }
}

struct SidebarButton: View {
    let title: String
    let symbol: String
    var count: Int? = nil
    var selected = false
    var indent: CGFloat = 0
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(selected ? RoseStyle.accent : .primary.opacity(0.65)).frame(width: 20)
                Text(title).font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if let count { Text(count.formatted()).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary) }
            }.padding(.leading, 13 + indent).padding(.trailing, 12).frame(height: 39)
                .background(selected ? RoseStyle.accent.opacity(0.13) : Color.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 12))
                .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.55), lineWidth: 0.7) } }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}

struct FolderTreeRow: View {
    @EnvironmentObject private var library: LibraryModel
    let folder: FolderNode
    let depth: Int
    let keyboard: GalleryKeyboard
    @State private var hovered = false

    private var expanded: Bool { library.expandedFolders.contains(folder.id) }
    private var selected: Bool { library.location == .folder(folder.id) }
    private var root: VaultRoot? { library.roots.first { $0.id == folder.rootID } }
    private var unavailable: Bool { root?.isAvailable == false }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Button {
                    if expanded { library.expandedFolders.remove(folder.id) } else { library.expandedFolders.insert(folder.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(width: 17, height: 34)
                        .opacity(folder.children.isEmpty ? 0 : 1)
                }.buttonStyle(.plain).disabled(folder.children.isEmpty)
                Button { library.location = .folder(folder.id) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: unavailable ? "folder.badge.questionmark" : (expanded && !folder.children.isEmpty ? "folder.fill" : "folder"))
                            .font(.system(size: 16, weight: .light)).foregroundStyle(selected ? RoseStyle.accent : .primary.opacity(0.6))
                        Text(folder.name).font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                        Spacer(minLength: 4)
                        if unavailable { Image(systemName: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.secondary) }
                        else { Text((library.recursive ? folder.imageCount : folder.directImageCount).formatted()).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
                    }.frame(height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.leading, 3 + CGFloat(depth) * 14).padding(.trailing, 12)
            .background(selected ? RoseStyle.accent.opacity(0.13) : Color.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 11))
            .overlay { if selected { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.5), lineWidth: 0.7) } }
            .onHover { hovered = $0 }.help(folder.url.path)
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path) }
                Button("Refresh Folder") { library.refresh(rootIDs: [folder.rootID]) }
                if depth == 0, let root {
                    Divider()
                    Button("Remove from Rose") { library.removeRoot(root) }
                }
            }
            .preservesImageSelection(using: keyboard)
            if expanded {
                ForEach(folder.children) { child in FolderTreeRow(folder: child, depth: depth + 1, keyboard: keyboard) }
            }
        }
    }
}
