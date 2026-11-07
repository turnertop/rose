import SwiftUI
import AppKit
import RoseCore
import RoseImaging

struct InspectorView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var tagPopover = false
    @State private var newTag = ""
    @State private var draftNote = ""
    @State private var loadedID: String?
    @State private var noteEdited = false
    @State private var editingNote = false
    @State private var noteTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let asset = library.selectedAsset { inspector(asset) }
            else { emptyInspector }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .roseGlass(radius: 23)
        .onAppear { loadNote() }
        .onChange(of: library.primaryID) { _, _ in flushNote(); loadNote() }
        .onChange(of: library.selectedAsset?.annotation.note) { _, value in
            if !noteEdited, let value { draftNote = value }
        }
        .onChange(of: draftNote) { _, _ in
            guard let id = loadedID, let asset = library.assets.first(where: { $0.id == id }), draftNote != asset.annotation.note else { return }
            noteEdited = true
            noteTask?.cancel()
            noteTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                flushNote()
            }
        }
        .onDisappear { flushNote() }
    }

    private func inspector(_ asset: ImageAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    SectionCaption(title: "A closer look")
                    Spacer(minLength: 2)
                    GlassIconButton(symbol: "chevron.left", help: "Previous image") { library.navigate(-1) }
                    GlassIconButton(symbol: "chevron.right", help: "Next image") { library.navigate(1) }
                }.padding(.bottom, 15)

                AssetPreview(asset: asset)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open viewer") { library.viewerPresented = true }
                            .roseGlass(radius: 11).padding(9)
                    }
                    .onTapGesture(count: 2) { library.viewerPresented = true }

                VStack(alignment: .leading, spacing: 6) {
                    Text(asset.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    Text("\(asset.dimensions)  ·  \(asset.fileExtension.uppercased())  ·  \(asset.formattedSize)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.top, 17)

                HStack(spacing: 7) {
                    GlassIconButton(symbol: asset.annotation.isFavorite ? "star.fill" : "star", help: asset.annotation.isFavorite ? "Remove from favorites" : "Add to favorites", active: asset.annotation.isFavorite) { library.toggleFavorite() }
                    GlassIconButton(symbol: "folder", help: "Show in Finder") { library.reveal() }
                    GlassIconButton(symbol: "link", help: "Copy file path") { library.copyPath() }
                    Menu {
                        Button("Copy Image") { library.copyImage() }
                        Button("Open in Default App") { NSWorkspace.shared.open(asset.url) }
                        ShareLink(item: asset.url) { Text("Share Image…") }
                        if !library.collections.isEmpty {
                            Menu("Add to Collection") {
                                ForEach(library.collections) { collection in Button(collection.name) { library.addToCollection(collection.id, paths: [asset.id]) } }
                            }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More image actions")
                    Spacer(minLength: 0)
                    GlassIconButton(symbol: "trash", help: "Move to Trash…") { library.trash() }
                }.padding(.top, 13).padding(.bottom, 18)

                divider
                HStack {
                    SectionCaption(title: "Tags")
                    Spacer()
                    Button { newTag = ""; tagPopover = true } label: { Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Add a tag")
                        .popover(isPresented: $tagPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Add a tag").font(.headline)
                                TextField("e.g. inspiration", text: $newTag).textFieldStyle(.roundedBorder).onSubmit { addTag(asset) }
                                HStack { Spacer(); Button("Add") { addTag(asset) }.buttonStyle(.borderedProminent).disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                            }.padding(18).frame(width: 240)
                        }
                }.padding(.top, 20).padding(.bottom, 13)

                if asset.annotation.tags.isEmpty {
                    Text("A few words to find it again.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 19)
                } else {
                    TagFlowLayout(spacing: 7) {
                        ForEach(asset.annotation.tags, id: \.self) { tag in
                            HStack(spacing: 6) {
                                Button { library.location = .tag(tag) } label: { Text("# \(tag)").font(.system(size: 11)) }.buttonStyle(.plain)
                                Button { library.updateAnnotation(id: asset.id) { $0.tags.removeAll { $0 == tag } } } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                                }.buttonStyle(.plain).help("Remove tag \(tag)")
                            }.padding(.horizontal, 10).padding(.vertical, 7).roseGlass(radius: 11)
                        }
                    }.padding(.bottom, 19)
                }
                divider

                HStack {
                    SectionCaption(title: "Notes")
                    Spacer()
                    Button { flushNote(); editingNote.toggle() } label: {
                        Image(systemName: editingNote ? "checkmark" : "square.and.pencil").font(.system(size: 12)).foregroundStyle(editingNote ? RoseStyle.accent : .secondary)
                    }.buttonStyle(.plain).help(editingNote ? "Finish editing" : "Edit Markdown note")
                }.padding(.top, 20).padding(.bottom, 13)

                Group {
                    if editingNote {
                        TextEditor(text: Binding(get: { draftNote }, set: { value in
                            draftNote = value
                            if let id = loadedID { library.stageNote(id: id, note: value) }
                        })).font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden).frame(minHeight: 145).padding(10)
                            .accessibilityLabel("Image note in Markdown")
                    } else if draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { editingNote = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("What caught your eye?").font(.system(size: 12, weight: .medium))
                                Text("Leave yourself a little note.\nMarkdown is welcome here.").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(4)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(15).frame(minHeight: 110)
                        }.buttonStyle(.plain)
                    } else {
                        MarkdownNote(text: draftNote).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.035), lineWidth: 1) }

                HStack(spacing: 5) {
                    Image(systemName: "doc.plaintext").font(.system(size: 9))
                    Text(noteEdited ? "Saving…" : (draftNote.isEmpty ? "Notes live beside your image as Markdown" : "Saved beside your image as Markdown"))
                }.font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 9).padding(.bottom, 22)
                divider

                VStack(alignment: .leading, spacing: 10) {
                    SectionCaption(title: "Location")
                    Button { library.reveal() } label: {
                        Label(asset.relativePath, systemImage: "folder").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain).help(asset.id)
                    Text("Modified \(asset.modifiedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 9)).foregroundStyle(.tertiary)
                }.padding(.top, 19).padding(.bottom, 4)
            }.padding(.horizontal, 21).padding(.top, 18).padding(.bottom, 22)
        }.scrollIndicators(.hidden)
    }

    private var divider: some View { Rectangle().fill(.primary.opacity(0.055)).frame(height: 1) }

    private var emptyInspector: some View {
        VStack(spacing: 13) {
            Image(systemName: "viewfinder").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(RoseStyle.accent.opacity(0.4))
            Text("Something will catch your eye.").font(.system(size: 14, weight: .medium, design: .rounded))
            Text("Select an image to see its details,\nadd tags, or leave a note.").font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }

    private func addTag(_ asset: ImageAsset) {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !tag.isEmpty else { return }
        library.updateAnnotation(id: asset.id) { annotation in
            if !annotation.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) { annotation.tags.append(tag) }
        }
        tagPopover = false
    }

    private func loadNote() {
        noteTask?.cancel(); noteTask = nil
        loadedID = library.selectedAsset?.id
        draftNote = library.selectedAsset?.annotation.note ?? ""
        noteEdited = false
    }

    private func flushNote() {
        noteTask?.cancel(); noteTask = nil
        guard noteEdited, let id = loadedID else { return }
        let note = draftNote
        library.saveNote(id: id, note: note)
        noteEdited = false
    }
}

private final class PreviewLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var failed = false
    private var operation: ThumbnailRequest?
    func load(_ asset: ImageAsset) {
        operation?.cancel(); image = nil; failed = false
        operation = ThumbnailService.shared.load(asset, maxPixel: 1800, priority: .preview) { [weak self] image in
            self?.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            self?.failed = image == nil
        }
    }
    func cancel() { operation?.cancel() }
    deinit { operation?.cancel() }
}

struct AssetPreview: View {
    let asset: ImageAsset
    @StateObject private var loader = PreviewLoader()
    var body: some View {
        ZStack {
            if let image = loader.image { Image(nsImage: image).resizable().scaledToFit() }
            else if loader.failed {
                VStack(spacing: 8) { Image(systemName: "photo.badge.exclamationmark"); Text("Preview unavailable").font(.caption) }.foregroundStyle(.secondary)
            } else { ProgressView().controlSize(.small) }
        }
        .onAppear { loader.load(asset) }
        .onChange(of: "\(asset.id)\(asset.modifiedAt.timeIntervalSince1970)") { _, _ in loader.load(asset) }
        .onDisappear { loader.cancel() }
    }
}

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 300).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

struct MarkdownNote: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.system(size: 18, weight: .semibold)).padding(.vertical, 3) }
                else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.system(size: 15, weight: .semibold)).padding(.vertical, 2) }
                else if line.hasPrefix("### ") { Text(String(line.dropFirst(4))).font(.system(size: 13, weight: .semibold)) }
                else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) { Text("•"); Text(.init(String(line.dropFirst(2)))) }.font(.system(size: 12))
                } else if line.isEmpty { Spacer().frame(height: 3) }
                else { Text(.init(line)).font(.system(size: 12)).textSelection(.enabled) }
            }
        }
    }
}
