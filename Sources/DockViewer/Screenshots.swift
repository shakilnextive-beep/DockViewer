import AppKit
import SwiftUI

/// Renders the README / store screenshots from the real preview views,
/// filled with sample data (no personal windows or tabs).
///
///   "/Applications/Dock Viewer.app/Contents/MacOS/DockViewer" --render-screenshots docs/images
@MainActor
enum Screenshots {
    static func render(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        save(Scene(content: AnyView(windowsPanel()), hovered: 2), size: CGSize(width: 1000, height: 600),
             to: out.appendingPathComponent("windows.png"))
        save(Scene(content: AnyView(tabsPanel()), hovered: 1), size: CGSize(width: 1000, height: 640),
             to: out.appendingPathComponent("tabs.png"))
        save(MenuMock(), size: CGSize(width: 340, height: 420), to: out.appendingPathComponent("menu.png"))
        print("screenshots written to \(out.path)")
    }

    // MARK: Sample content

    private static let notesIcon = MockIcon.image(MockIcon.apps[2])
    private static let safariIcon = MockIcon.image(MockIcon.apps[1])

    private static func windowsPanel() -> some View {
        let model = PreviewModel()
        model.appName = "Notes"
        model.icon = notesIcon
        let dummy = AXUIElementCreateSystemWide()
        model.windows = [
            WindowInfo(id: 1, element: dummy, title: "Project ideas", minimized: false, origin: .zero,
                       image: snapshot(MockDoc(accent: .orange, title: "Project ideas", seed: 1))),
            WindowInfo(id: 2, element: dummy, title: "Shopping list", minimized: false, origin: .zero,
                       image: snapshot(MockDoc(accent: .yellow, title: "Shopping list", seed: 2))),
            WindowInfo(id: 3, element: dummy, title: "Meeting notes", minimized: true, origin: .zero,
                       image: snapshot(MockDoc(accent: .green, title: "Meeting notes", seed: 3))),
        ]
        model.hovered = 1
        return PanelChrome { PreviewView(model: model) }
    }

    private static func tabsPanel() -> some View {
        let model = PreviewModel()
        model.appName = "Safari"
        model.icon = safariIcon
        model.isBrowser = true
        model.mode = .tabs
        model.tabLayout = .grid
        let dummy = AXUIElementCreateSystemWide()
        model.windows = [WindowInfo(id: 1, element: dummy, title: "", minimized: false, origin: .zero, image: nil),
                         WindowInfo(id: 2, element: dummy, title: "", minimized: false, origin: .zero, image: nil)]
        let pages: [(String, String, Color, Bool)] = [
            ("Lo-fi beats to relax", "https://youtube.com/watch", .red, true),
            ("DockViewer — GitHub", "https://github.com/dockviewer", Color(white: 0.2), true),
            ("Inbox (3)", "https://mail.example.com", .blue, true),
            ("Travel plan — Docs", "https://docs.example.com", Color(red: 0.2, green: 0.5, blue: 1), true),
            ("Mac Dock — Wikipedia", "https://en.wikipedia.org/wiki/Dock", Color(white: 0.85), true),
            ("Weather this week", "https://weather.example.com", .teal, false),
            ("Recipes — Easy pasta", "https://recipes.example.com", .orange, true),
            ("News — Technology", "https://news.example.com", .purple, false),
        ]
        model.tabs = pages.enumerated().map { i, p in
            TabInfo(id: i, windowID: "1", windowOrigin: .zero, windowNumber: 1, index: i + 1, active: i == 1,
                    key: "\(i)", title: p.0, url: p.1,
                    image: p.3 ? snapshot(MockPage(color: p.2, title: p.0, seed: i)) : nil)
        }
        model.hoveredTab = 2
        return PanelChrome { PreviewView(model: model) }
    }

    // MARK: Rendering

    private static func snapshot<V: View>(_ view: V) -> CGImage? {
        let r = ImageRenderer(content: view.frame(width: 640, height: 400))
        r.scale = 1
        return r.cgImage
    }

    private static func save<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                   pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - Scene: wallpaper + popup + Dock

private struct PanelChrome<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.125, green: 0.125, blue: 0.125)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }
}

/// Colorful stand-in app icons (system icons may render tinted/grey).
private struct MockIcon: View {
    struct App { let symbol: String; let top: Color; let bottom: Color }
    static let apps: [App] = [
        App(symbol: "face.smiling", top: Color(red: 0.35, green: 0.75, blue: 1), bottom: Color(red: 0.1, green: 0.45, blue: 0.95)),
        App(symbol: "safari", top: Color(red: 0.3, green: 0.7, blue: 1), bottom: Color(red: 0.05, green: 0.4, blue: 0.9)),
        App(symbol: "note.text", top: Color(red: 1, green: 0.85, blue: 0.3), bottom: Color(red: 1, green: 0.65, blue: 0.1)),
        App(symbol: "calendar", top: Color(red: 1, green: 0.4, blue: 0.4), bottom: Color(red: 0.85, green: 0.15, blue: 0.2)),
        App(symbol: "music.note", top: Color(red: 1, green: 0.4, blue: 0.6), bottom: Color(red: 0.9, green: 0.15, blue: 0.4)),
        App(symbol: "gearshape.fill", top: Color(white: 0.6), bottom: Color(white: 0.35)),
    ]
    let app: App
    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(LinearGradient(colors: [app.top, app.bottom], startPoint: .top, endPoint: .bottom))
            .overlay(Image(systemName: app.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white))
            .frame(width: 58, height: 58)
    }

    @MainActor static func image(_ app: App) -> NSImage {
        let r = ImageRenderer(content: MockIcon(app: app))
        r.scale = 2
        return r.nsImage ?? NSImage()
    }
}

private struct Scene: View {
    let content: AnyView
    let hovered: Int
    private let dockApps = MockIcon.apps

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.40), Color(red: 0.45, green: 0.25, blue: 0.55),
                                    Color(red: 0.95, green: 0.55, blue: 0.45)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 700).offset(x: 300, y: -260)
            VStack(spacing: 14) {
                content
                HStack(spacing: 10) {
                    ForEach(Array(dockApps.enumerated()), id: \.offset) { i, app in
                        VStack(spacing: 4) {
                            MockIcon(app: app)
                            Circle().fill(Color.white.opacity(i == hovered || i == 1 || i == 2 ? 0.85 : 0))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            }
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Mock window contents

private struct MockDoc: View {
    let accent: Color
    let title: String
    let seed: Int
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<6) { i in
                    RoundedRectangle(cornerRadius: 4).fill(i == seed % 6 ? accent.opacity(0.7) : Color.white.opacity(0.12))
                        .frame(height: 22)
                }
                Spacer()
            }
            .padding(16).frame(width: 170).background(Color(white: 0.16))
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                ForEach(0..<7) { i in
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.22))
                        .frame(width: CGFloat(380 - ((i * 47 + seed * 31) % 170)), height: 14)
                }
                Spacer()
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.11))
        }
    }
}

private struct MockPage: View {
    let color: Color
    let title: String
    let seed: Int
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(Color.white.opacity(0.9)).frame(width: 26, height: 26)
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.85)).frame(width: 140, height: 16)
                Spacer()
            }
            .padding(.horizontal, 20).frame(height: 64).background(color)
            HStack(alignment: .top, spacing: 18) {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.35)).frame(width: 300, height: 220)
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.black.opacity(0.8)).lineLimit(2)
                    ForEach(0..<6) { i in
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.14))
                            .frame(width: CGFloat(240 - ((i * 37 + seed * 23) % 110)), height: 12)
                    }
                }
                Spacer()
            }
            .padding(22)
            Spacer()
        }
        .background(Color.white)
    }
}

// MARK: - Menu bar menu

private struct MenuMock: View {
    private let rows: [(String, Bool, Bool)] = [   // title, checked, separatorAfter
        ("Dock Viewer 1.0.0", false, false),
        ("Accessibility: ✓ Allowed", false, false),
        ("Screen Recording: ✓ Allowed", false, true),
        ("Click Dock Icon to Minimize / Restore", true, false),
        ("Preview Speed  ›", false, false),
        ("Open at Login", true, false),
        ("Install Updates Automatically", true, false),
        ("Check for Updates…", false, true),
        ("Share Dock Viewer…", false, false),
        ("Visit SupportKori", false, false),
        ("About Dock Viewer", false, true),
        ("Quit Dock Viewer", false, false),
    ]
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.40), Color(red: 0.45, green: 0.25, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 6) {
                        Text(row.1 ? "✓" : " ").frame(width: 12)
                        Text(row.0).foregroundStyle(i == 0 ? Color.white.opacity(0.5) : .white)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).frame(height: 24)
                    if row.2 { Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4).padding(.horizontal, 10) }
                }
            }
            .padding(.vertical, 6)
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.17)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        }
    }
}
