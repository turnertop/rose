import SwiftUI
import AppKit

@main
struct RoseApp: App {
    @NSApplicationDelegateAdaptor(RoseAppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryModel()
    @AppStorage("rose.appearance") private var appearance = "light"

    var body: some Scene {
        WindowGroup("Rose") {
            LibraryView()
                .environmentObject(library)
                .tint(RoseStyle.accent)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .onAppear { appDelegate.library = library }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900)
        .commands { RoseCommands(library: library) }

        Settings { SettingsView() }
    }
}

@MainActor
final class RoseAppDelegate: NSObject, NSApplicationDelegate {
    weak var library: LibraryModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) { library?.flush() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, open urls: [URL]) { library?.connect(urls) }
}

struct RoseCommands: Commands {
    @ObservedObject var library: LibraryModel
    @AppStorage("rose.staticSurfaces") private var staticSurfaces = RoseStyle.defaultStaticSurfaces

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…", action: library.chooseFolder).keyboardShortcut("o")
            Button("New Collection…") { library.collectionSheet = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Refresh Library") { library.refresh() }.keyboardShortcut("r")
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Image") { library.copyImage() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(library.selectedAsset == nil)
            Button("Copy File Path") { library.copyPath() }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(library.selectedAsset == nil)
        }
        CommandMenu("Image") {
            Button("Open Viewer") { library.viewerPresented = true }.keyboardShortcut(.return).disabled(library.selectedAsset == nil)
            Button("Toggle Favorite") { library.toggleFavorite() }.keyboardShortcut("d").disabled(library.selectedAsset == nil)
            Button("Show in Finder") { library.reveal() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(library.selectedAsset == nil)
            Divider()
            Button("Previous Image") { library.navigate(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("Next Image") { library.navigate(1) }.keyboardShortcut(.rightArrow, modifiers: [.command])
        }
        CommandGroup(after: .sidebar) {
            Button(library.showSidebar ? "Hide Sidebar" : "Show Sidebar", action: library.toggleSidebar)
                .keyboardShortcut("s", modifiers: [.control, .command])
            Button(library.showInspector ? "Hide Inspector" : "Show Inspector", action: library.toggleInspector)
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Include Subfolders", isOn: $library.recursive)
            Divider()
            Toggle("Static Surfaces", isOn: $staticSurfaces)
            Divider()
            Button("Fill View") { library.displayMode = .fill }.keyboardShortcut("1")
            Button("Fit View") { library.displayMode = .fit }.keyboardShortcut("2")
            Button("List View") { library.displayMode = .list }.keyboardShortcut("3")
        }
    }
}

struct SettingsView: View {
    @AppStorage("rose.appearance") private var appearance = "light"
    @AppStorage("rose.staticSurfaces") private var staticSurfaces = RoseStyle.defaultStaticSurfaces
    @AppStorage(ViewerScrollZoomPreference.key) private var twoFingerScrollZoom = ViewerScrollZoomPreference.defaultValue
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("A little home for your references.", systemImage: "sparkle").font(.title3.weight(.semibold))
                Text("Rose browses your folders directly. Images stay in place, and annotations are saved beside them as image.jpg.md files.")
                    .foregroundStyle(.secondary)
                Picker("Appearance", selection: $appearance) {
                    Text("Pink").tag("light")
                    Text("Dark rose").tag("dark")
                    Text("Follow system").tag("system")
                }.pickerStyle(.segmented)
                Toggle(isOn: $staticSurfaces) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Static surfaces")
                        Text("Same palette and layout, with fewer visual effects.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("IMAGE VIEWER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Toggle(isOn: $twoFingerScrollZoom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Two-finger scroll to zoom")
                        Text("Slide two fingers up to zoom in and down to zoom out. Drag to pan. Pinch still works.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("KEYBOARD SHORTCUTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                shortcut("Open a folder", "⌘ O")
                shortcut("Focus search for editing", "⌘ F")
                shortcut("Start a new search while browsing", "Type")
                shortcut("Leave search, keeping the query", "Esc")
                shortcut("Scroll with no image selected", "Space / ⇧ Space")
                shortcut("Open selected image / close viewer", "Space")
                shortcut("Clear gallery selection / close viewer", "Esc")
                shortcut("Navigate images", "← ↑ ↓ →")
                shortcut("Toggle favorite", "⌘ D")
                shortcut("Show in Finder", "⇧ ⌘ R")
                shortcut("Toggle sidebar", "⌃ ⌘ S")
                shortcut("Toggle inspector", "⌥ ⌘ I")
                shortcut("Fill / Fit / List view", "⌘ 1 / 2 / 3")
                shortcut("Viewer: fit / actual size", "0 / 1")
                shortcut("Viewer: zoom", "+ / − or pinch")
                Text("Made for files you own. No account, no uploads.").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.padding(30)
        }.frame(width: 460, height: 680)
    }

    private func shortcut(_ label: String, _ keys: String) -> some View {
        HStack { Text(label); Spacer(); Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
    }
}
