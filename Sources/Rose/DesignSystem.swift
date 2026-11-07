import SwiftUI
import AppKit

enum RoseStyle {
    static let defaultStaticSurfaces = true
    static let accent = Color(red: 0.94, green: 0.21, blue: 0.52)
    static let nsAccent = NSColor(srgbRed: 0.94, green: 0.21, blue: 0.52, alpha: 1)
    static let ink = Color(red: 0.24, green: 0.12, blue: 0.21)
}

private struct RoseStaticSurfacesKey: EnvironmentKey {
    static let defaultValue = RoseStyle.defaultStaticSurfaces
}

extension EnvironmentValues {
    var roseStaticSurfaces: Bool {
        get { self[RoseStaticSurfacesKey.self] }
        set { self[RoseStaticSurfacesKey.self] = newValue }
    }
}

struct RoseBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.roseStaticSurfaces) private var staticSurfaces

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if staticSurfaces {
                    LinearGradient(colors: scheme == .dark
                        ? [Color(red: 0.16, green: 0.10, blue: 0.14), Color(red: 0.12, green: 0.09, blue: 0.12), Color(red: 0.20, green: 0.10, blue: 0.16)]
                        : [Color(red: 1, green: 0.84, blue: 0.89), Color(red: 0.99, green: 0.94, blue: 0.96), Color(red: 1, green: 0.86, blue: 0.93)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    (scheme == .dark ? Color(red: 0.12, green: 0.09, blue: 0.12) : Color(red: 0.99, green: 0.94, blue: 0.96))
                    Ellipse().fill(Color.pink.opacity(scheme == .dark ? 0.15 : 0.20))
                        .frame(width: geometry.size.width * 0.80, height: geometry.size.height * 1.1)
                        .blur(radius: 100).offset(x: -geometry.size.width * 0.4, y: -geometry.size.height * 0.1)
                    Ellipse().fill(Color(red: 1, green: 0.62, blue: 0.73).opacity(scheme == .dark ? 0.12 : 0.23))
                        .frame(width: geometry.size.width * 0.7, height: geometry.size.height * 0.7)
                        .blur(radius: 95).offset(x: geometry.size.width * 0.38, y: geometry.size.height * 0.35)
                    Ellipse().stroke(.white.opacity(scheme == .dark ? 0.04 : 0.48), lineWidth: 1.5)
                        .frame(width: geometry.size.width * 1.4, height: geometry.size.height * 0.9)
                        .rotationEffect(.degrees(-32)).offset(y: geometry.size.height * 0.5).blur(radius: 2)
                }
            }
        }.ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 22
    var tintOpacity: Double = 0.035
    @Environment(\.colorScheme) private var scheme
    @Environment(\.roseStaticSurfaces) private var staticSurfaces
    func body(content: Content) -> some View {
        content
            .background { RoseGlassSurface(radius: radius, tint: tintOpacity) }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.18 : 0.88), .white.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(staticSurfaces ? 0 : (scheme == .dark ? 0.08 : 0.025)),
                    radius: staticSurfaces ? 0 : 16, x: 0, y: staticSurfaces ? 0 : 7)
    }
}

struct RoseGlassSurface: View {
    var radius: CGFloat = 0
    var tint: Double = 0.035
    var material: Material = .ultraThin
    var tinted = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.roseStaticSurfaces) private var staticSurfaces
    var body: some View {
        if staticSurfaces {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: scheme == .dark
                    ? [Color(red: 0.18, green: 0.13, blue: 0.17), Color(red: 0.16, green: 0.11, blue: 0.15)]
                    : [Color(red: 0.995, green: 0.965, blue: 0.977), Color(red: 0.98, green: 0.86, blue: 0.92)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            RoundedRectangle(cornerRadius: radius).fill(material)
                .overlay {
                    if tinted {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(LinearGradient(colors: scheme == .dark
                                ? [RoseStyle.accent.opacity(tint + 0.025), RoseStyle.accent.opacity(tint)]
                                : [.white.opacity(0.58), Color(red: 1, green: 0.87, blue: 0.94).opacity(0.68)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
        }
    }
}

extension View {
    func roseGlass(radius: CGFloat = 22, tint: Double = 0.035) -> some View {
        modifier(GlassPanel(radius: radius, tintOpacity: tint))
    }
}

struct GlassIconButton: View {
    let symbol: String
    let help: String
    var active = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? RoseStyle.accent : .primary.opacity(0.76))
                .frame(width: 34, height: 34)
                .background(active ? RoseStyle.accent.opacity(0.11) : Color.primary.opacity(hovered ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovered = $0 }
    }
}

struct DisplayModeButton: View {
    let mode: LibraryDisplayMode
    let active: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(mode.title).font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? RoseStyle.accent : .primary.opacity(0.7))
                .frame(width: 45, height: 32)
                .background(active ? RoseStyle.accent.opacity(0.12) : Color.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).help(mode.help).accessibilityLabel("\(mode.title) view")
        .accessibilityAddTraits(active ? .isSelected : [])
        .onHover { hovered = $0 }
    }
}

struct RoseMark: View {
    var size: CGFloat = 43
    @Environment(\.roseStaticSurfaces) private var staticSurfaces
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.68, blue: 0.81), RoseStyle.accent, Color(red: 0.83, green: 0.17, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(.white.opacity(0.65), lineWidth: 1) }
                .shadow(color: RoseStyle.accent.opacity(staticSurfaces ? 0 : 0.25), radius: staticSurfaces ? 0 : 7, y: staticSurfaces ? 0 : 3)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: size * 0.47, weight: .light)).foregroundStyle(.white)
        }.frame(width: size, height: size)
    }
}

struct SectionCaption: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.7).foregroundStyle(.secondary)
    }
}

@MainActor
struct WindowAccessor: NSViewRepresentable {
    @Environment(\.roseStaticSurfaces) private var staticSurfaces
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> RoseWindowStyleView {
        let view = RoseWindowStyleView(frame: .zero)
        view.configure(staticSurfaces: staticSurfaces, dark: scheme == .dark)
        return view
    }
    func updateNSView(_ view: RoseWindowStyleView, context: Context) {
        view.configure(staticSurfaces: staticSurfaces, dark: scheme == .dark)
    }
}

@MainActor
final class RoseWindowStyleView: NSView {
    private weak var configuredWindow: NSWindow?
    private var staticSurfaces = false
    private var dark = false
    private var appliedStatic: Bool?
    private var appliedDark: Bool?

    func configure(staticSurfaces: Bool, dark: Bool) {
        self.staticSurfaces = staticSurfaces; self.dark = dark
        applyWindowStyle()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyWindowStyle() }

    private func applyWindowStyle() {
        guard let window else { return }
        if configuredWindow !== window {
            configuredWindow = window; appliedStatic = nil; appliedDark = nil
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 1060, height: 680)
        }
        // Don't reconfigure the native window for unrelated SwiftUI/model updates.
        guard appliedStatic != staticSurfaces || appliedDark != dark else { return }
        window.backgroundColor = staticSurfaces
            ? (dark ? NSColor(srgbRed: 0.12, green: 0.09, blue: 0.12, alpha: 1)
                    : NSColor(srgbRed: 0.99, green: 0.94, blue: 0.96, alpha: 1))
            : .clear
        window.isOpaque = staticSurfaces
        window.hasShadow = !staticSurfaces
        appliedStatic = staticSurfaces; appliedDark = dark
    }
}

struct PanelResizeHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let direction: CGFloat
    let label: String
    @State private var initialWidth: CGFloat?
    @State private var hovered = false

    var body: some View {
        Color.clear.frame(width: 6).contentShape(Rectangle())
            .overlay { Capsule().fill(RoseStyle.accent.opacity(hovered ? 0.3 : 0)).frame(width: 2, height: 32) }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if initialWidth == nil { initialWidth = width }
                width = min(range.upperBound, max(range.lowerBound, (initialWidth ?? width) + value.translation.width * direction))
            }.onEnded { _ in initialWidth = nil })
            .onHover { value in
                guard hovered != value else { return }
                hovered = value
                if value { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .accessibilityElement().accessibilityLabel(label).accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { adjustment in
                width = min(range.upperBound, max(range.lowerBound, width + (adjustment == .increment ? 10 : -10)))
            }
    }
}
