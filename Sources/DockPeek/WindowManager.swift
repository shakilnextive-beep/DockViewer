import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let element: AXUIElement
    let title: String
    let minimized: Bool
    var image: CGImage?
}

/// Lists an app's windows through Accessibility, captures thumbnails with
/// ScreenCaptureKit, and remembers the last image of every window so a
/// minimized window (which macOS can't capture) still has a picture.
final class WindowManager {
    static let shared = WindowManager()
    private var cache: [CGWindowID: CGImage] = [:]
    private let maxThumb: CGFloat = 480

    func runningApp(for url: URL?) -> NSRunningApplication? {
        guard let url else { return nil }
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
    }

    func windows(for app: NSRunningApplication) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axApp.elements(kAXWindowsAttribute).compactMap { w in
            // Many apps (WhatsApp, Adobe, Electron) report their main window as
            // AXDialog, not AXStandardWindow — accept both, skip tiny helpers.
            let okSubrole = [kAXStandardWindowSubrole, kAXDialogSubrole].contains(w.subrole ?? "")
            let size = w.size ?? .zero
            guard okSubrole, size.width >= 120, size.height >= 80, let id = w.windowID else { return nil }
            let title = w.string(kAXTitleAttribute) ?? ""
            return WindowInfo(id: id,
                              element: w,
                              title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                              minimized: w.bool(kAXMinimizedAttribute) ?? false,
                              image: cache[id])
        }
    }

    /// Captures fresh thumbnails for visible windows, and tries minimized
    /// windows too when we have no picture of them yet (macOS often still
    /// holds their last frame).
    func refreshThumbnails(_ windows: [WindowInfo]) async -> [CGWindowID: CGImage] {
        let ids = Set(windows.filter { !$0.minimized || $0.image == nil }.map(\.id))
        guard !ids.isEmpty, CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }

        var result: [CGWindowID: CGImage] = [:]
        for scWindow in content.windows where ids.contains(scWindow.windowID) {
            let frame = scWindow.frame
            guard frame.width > 1, frame.height > 1 else { continue }
            let scale = min(1, maxThumb / max(frame.width, frame.height)) * 2  // 2x for Retina sharpness
            let config = SCStreamConfiguration()
            config.width = Int(frame.width * scale)
            config.height = Int(frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                if !Self.isBlank(image) { result[scWindow.windowID] = image }
                else { Log.write("capture: window \(scWindow.windowID) came back blank") }
            } catch {
                Log.write("capture: window \(scWindow.windowID) failed: \(error.localizedDescription)")
            }
        }
        let captured = result
        await MainActor.run { cache.merge(captured) { $1 } }
        return captured
    }

    /// Keeps the frontmost app's window pictures fresh, so the moment a
    /// window gets minimized we already hold a recent image of it.
    func warmCacheForFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let list = windows(for: app)
        Task { _ = await refreshThumbnails(list) }
    }

    func focus(_ window: WindowInfo, in app: NSRunningApplication) {
        if window.minimized { window.element.set(kAXMinimizedAttribute, false) }
        app.activate()
        window.element.perform(kAXRaiseAction)
        window.element.set(kAXMainAttribute, true)
    }

    /// A minimized window sometimes captures as a fully transparent image.
    private static func isBlank(_ image: CGImage) -> Bool {
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 }
    }

    func minimize(_ window: WindowInfo) {
        if let image = window.image { cache[window.id] = image }  // keep its picture
        window.element.set(kAXMinimizedAttribute, true)
    }

    /// Green button: bring the window forward, then press its own zoom button.
    func zoom(_ window: WindowInfo, in app: NSRunningApplication) {
        focus(window, in: app)
        DispatchQueue.main.asyncAfter(deadline: .now() + (window.minimized ? 0.45 : 0.1)) {
            window.element.element(kAXZoomButtonAttribute)?.perform(kAXPressAction)
        }
    }

    func close(_ window: WindowInfo) {
        window.element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        cache[window.id] = nil
    }
}
