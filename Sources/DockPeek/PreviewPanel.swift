import AppKit
import SwiftUI

// MARK: - Model

enum TileButton { case close, minimize, zoom }

final class PreviewModel: ObservableObject {
    @Published var appName = ""
    @Published var icon = NSImage()
    @Published var windows: [WindowInfo] = []
    @Published var hovered: CGWindowID?
    @Published var hoveredButton: TileButton?
    /// Tile and button rects in the panel's top-left coordinate space.
    /// Hover is computed from the mouse position because SwiftUI's onHover
    /// doesn't fire in a panel that belongs to an inactive app.
    var tileFrames: [CGWindowID: CGRect] = [:]
    var buttonFrames: [CGWindowID: [TileButton: CGRect]] = [:]
    var onOpen: (WindowInfo) -> Void = { _ in }
    var onClose: (WindowInfo) -> Void = { _ in }
    var onMinimize: (WindowInfo) -> Void = { _ in }
    var onZoom: (WindowInfo) -> Void = { _ in }

    func updateHover(at point: CGPoint?) {
        var tile: CGWindowID?
        var button: TileButton?
        if let point {
            tile = tileFrames.first { $0.value.contains(point) }?.key
            if let tile, let buttons = buttonFrames[tile] {
                button = buttons.first { $0.value.contains(point) }?.key
            }
        }
        if hovered != tile { hovered = tile }
        if hoveredButton != button { hoveredButton = button }
    }
}

private struct FrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func reportFrame(_ key: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: FrameKey.self, value: [key: g.frame(in: .named("panel"))])
        })
    }
}

// MARK: - Windows 11 style palette

enum Win11 {
    static let panel = Color(red: 0.125, green: 0.125, blue: 0.125)        // #202020
    static let border = Color.white.opacity(0.08)
    static let tileHover = Color.white.opacity(0.07)
    static let buttonHover = Color.white.opacity(0.10)
    static let closeRed = Color(red: 0.77, green: 0.17, blue: 0.11)        // #C42B1C
    static let text = Color.white.opacity(0.92)
    static let subtext = Color.white.opacity(0.55)
    static let accent = Color(red: 0.30, green: 0.69, blue: 1.0)           // Windows blue
}

// MARK: - Views

struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    private var tileWidth: CGFloat { model.windows.count > 5 ? 180 : 224 }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(tileWidth), spacing: 4), count: min(max(model.windows.count, 1), 5))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(model.windows) { w in
                WindowTile(model: model, window: w, icon: model.icon, width: tileWidth)
            }
        }
        .padding(6)
        .fixedSize()
        .coordinateSpace(name: "panel")
        .onPreferenceChange(FrameKey.self) { frames in
            var tiles: [CGWindowID: CGRect] = [:]
            var buttons: [CGWindowID: [TileButton: CGRect]] = [:]
            for (key, rect) in frames {
                let parts = key.split(separator: ":")
                guard parts.count == 2, let id = CGWindowID(parts[1]) else { continue }
                switch parts[0] {
                case "tile": tiles[id] = rect
                case "close": buttons[id, default: [:]][.close] = rect
                case "min": buttons[id, default: [:]][.minimize] = rect
                case "zoom": buttons[id, default: [:]][.zoom] = rect
                default: break
                }
            }
            model.tileFrames = tiles
            model.buttonFrames = buttons
        }
    }
}

/// A macOS "traffic light" button: red close, yellow minimize, green zoom.
/// Glyphs appear while the mouse is over the tile, just like a Mac window.
struct TrafficLight: View {
    enum Kind { case close, minimize, zoom }
    let kind: Kind
    let enabled: Bool
    let showGlyph: Bool
    let pressed: Bool
    let action: () -> Void

    private var fill: Color {
        guard enabled else { return Color(white: 0.38) }
        switch kind {
        case .close: return Color(red: 1.00, green: 0.37, blue: 0.34)     // #FF5F57
        case .minimize: return Color(red: 1.00, green: 0.74, blue: 0.18)  // #FEBC2E
        case .zoom: return Color(red: 0.16, green: 0.78, blue: 0.25)      // #28C840
        }
    }

    private var stroke: Color {
        guard enabled else { return Color(white: 0.30) }
        switch kind {
        case .close: return Color(red: 0.88, green: 0.27, blue: 0.24)
        case .minimize: return Color(red: 0.87, green: 0.62, blue: 0.13)
        case .zoom: return Color(red: 0.11, green: 0.65, blue: 0.19)
        }
    }

    private var glyph: some View {
        Group {
            switch kind {
            case .close: Image(systemName: "xmark").font(.system(size: 7, weight: .black))
            case .minimize: Image(systemName: "minus").font(.system(size: 8, weight: .black))
            case .zoom: Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 6.5, weight: .black))
            }
        }
        .foregroundStyle(Color.black.opacity(0.55))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: 0.5)
                if showGlyph && enabled { glyph }
                if pressed && enabled { Circle().fill(Color.black.opacity(0.18)) }
            }
            .frame(width: 13, height: 13)
            .padding(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct WindowTile: View {
    @ObservedObject var model: PreviewModel
    let window: WindowInfo
    let icon: NSImage
    let width: CGFloat

    private var hovering: Bool { model.hovered == window.id }
    private var thumbWidth: CGFloat { width - 16 }
    private var thumbHeight: CGFloat { thumbWidth * 0.6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title bar, Mac style: traffic lights on the left, then icon + title
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    TrafficLight(kind: .close, enabled: true, showGlyph: hovering,
                                 pressed: hovering && model.hoveredButton == .close) {
                        model.onClose(window)
                    }
                    .reportFrame("close:\(window.id)")
                    TrafficLight(kind: .minimize, enabled: !window.minimized, showGlyph: hovering,
                                 pressed: hovering && model.hoveredButton == .minimize) {
                        model.onMinimize(window)
                    }
                    .reportFrame("min:\(window.id)")
                    TrafficLight(kind: .zoom, enabled: true, showGlyph: hovering,
                                 pressed: hovering && model.hoveredButton == .zoom) {
                        model.onZoom(window)
                    }
                    .reportFrame("zoom:\(window.id)")
                }
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                Text(window.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Win11.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(height: 24)

            // Thumbnail
            thumbnail
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomLeading) {
                    if window.minimized {
                        Text("Minimized")
                            .font(.system(size: 10))
                            .foregroundStyle(Win11.text)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.6)))
                            .padding(5)
                    }
                }
        }
        .padding(8)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Win11.tileHover : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hovering ? Win11.border : .clear, lineWidth: 1)
        )
        .reportFrame("tile:\(window.id)")
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture { model.onOpen(window) }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = window.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbWidth, height: thumbHeight)
                .opacity(window.minimized ? 0.7 : 1)
        } else {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.04))
                Image(nsImage: icon).resizable().frame(width: 40, height: 40).opacity(0.7)
            }
        }
    }
}

/// Lets the first click on the popup act immediately, even though the
/// popup's app is never active.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Panel

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PreviewController {
    private let panel: PreviewPanel
    private let hosting: ClickThroughHostingView<PreviewView>
    let model = PreviewModel()
    private(set) var currentApp: NSRunningApplication?
    private var itemFrame: CGRect = .zero

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var anchorFrame: CGRect { itemFrame }

    init() {
        panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Windows 11 style: solid dark card, thin light border, 8pt corners.
        let glass = NSView()
        glass.wantsLayer = true
        glass.layer?.backgroundColor = NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 0.98).cgColor
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        glass.layer?.borderWidth = 1
        glass.layer?.cornerRadius = 8
        glass.layer?.masksToBounds = true
        glass.appearance = NSAppearance(named: .darkAqua)

        hosting = ClickThroughHostingView(rootView: PreviewView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glass.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass

        model.onOpen = { [weak self] w in
            guard let self, let app = currentApp else { return }
            WindowManager.shared.focus(w, in: app)
            hide()
        }
        model.onMinimize = { [weak self] w in
            WindowManager.shared.minimize(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.reload() }
        }
        model.onZoom = { [weak self] w in
            guard let self, let app = currentApp else { return }
            WindowManager.shared.zoom(w, in: app)
            hide()
        }
        model.onClose = { [weak self] w in
            WindowManager.shared.close(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.reload() }
        }
    }

    func show(app: NSRunningApplication, at item: DockItem) {
        currentApp = app
        itemFrame = item.frame
        model.appName = app.localizedName ?? item.title
        model.icon = app.icon ?? NSImage()
        model.windows = WindowManager.shared.windows(for: app)
        guard !model.windows.isEmpty else { hide(); return }
        layoutAndShow()
        refreshImages()
    }

    /// Called on a timer with the global mouse position.
    func trackMouse(_ location: CGPoint) {
        guard panel.isVisible else { return }
        let f = panel.frame
        let local = CGPoint(x: location.x - f.minX, y: f.maxY - location.y)  // flip to top-left
        let inside = local.x >= 0 && local.y >= 0 && local.x <= f.width && local.y <= f.height
        model.updateHover(at: inside ? local : nil)
    }

    func hide() {
        model.updateHover(at: nil)
        panel.orderOut(nil)
        currentApp = nil
    }

    private func reload() {
        guard let app = currentApp else { return }
        model.windows = WindowManager.shared.windows(for: app)
        if model.windows.isEmpty { hide() } else { layoutAndShow(); refreshImages() }
    }

    private func refreshImages() {
        let pid = currentApp?.processIdentifier
        let list = model.windows
        Task { @MainActor in
            let fresh = await WindowManager.shared.refreshThumbnails(list)
            guard currentApp?.processIdentifier == pid, !fresh.isEmpty else { return }
            model.windows = model.windows.map { w in
                var w = w
                if let img = fresh[w.id] { w.image = img }
                return w
            }
        }
    }

    private func layoutAndShow() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(itemFrame) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let gap: CGFloat = 10
        var origin: CGPoint

        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom" {
        case "left":
            origin = CGPoint(x: itemFrame.maxX + gap, y: itemFrame.midY - size.height / 2)
        case "right":
            origin = CGPoint(x: itemFrame.minX - gap - size.width, y: itemFrame.midY - size.height / 2)
        default:
            origin = CGPoint(x: itemFrame.midX - size.width / 2, y: itemFrame.maxY + gap)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height - 8)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
    }
}
