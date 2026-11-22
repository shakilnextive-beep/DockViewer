import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watcher = DockWatcher()
    private let preview = PreviewController()
    private let clicks = DockClickHandler()
    private var statusItem: NSStatusItem!
    private var pendingShow: DispatchWorkItem?
    private var hoverTimer: Timer?
    private var outsideSince: Date?
    private var cacheTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.reset()
        Log.write("launch: AX=\(AXIsProcessTrusted()) ScreenRecording=\(CGPreflightScreenCaptureAccess())")
        setupMenuBar()
        requestPermissions()

        watcher.onHover = { [weak self] item in self?.dockHoverChanged(item) }
        watcher.start()

        clicks.currentItem = { [weak self] in self?.watcher.current }
        clicks.willHandleClick = { [weak self] in
            self?.pendingShow?.cancel()
            self?.preview.hide()
        }
        clicks.start()

        // Keep thumbnails fresh so minimized windows still have a picture.
        cacheTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            WindowManager.shared.warmCacheForFrontmostApp()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in WindowManager.shared.warmCacheForFrontmostApp() }
    }

    // MARK: Hover logic

    /// How long the mouse must rest on a Dock icon before the popup opens.
    static let delayChoices: [(title: String, seconds: Double)] = [
        ("দ্রুত (0.2 সেকেন্ড)", 0.2), ("মাঝারি (0.4 সেকেন্ড)", 0.4), ("ধীরে (0.7 সেকেন্ড)", 0.7),
    ]
    static var hoverDelay: Double {
        get { UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.4 }
        set { UserDefaults.standard.set(newValue, forKey: "hoverDelay") }
    }

    private func dockHoverChanged(_ item: DockItem?) {
        pendingShow?.cancel()
        guard let item else { return }   // mouse left an icon; the hover timer decides when to hide
        guard let app = WindowManager.shared.runningApp(for: item.appURL) else {
            Log.write("hover: no running app for \(item.title)"); return
        }
        Log.write("hover: \(app.localizedName ?? "?") windows=\(WindowManager.shared.windows(for: app).count)")
        if preview.isVisible {
            preview.show(app: app, at: item)          // already open: switch instantly
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.preview.show(app: app, at: item)
                self?.startHoverTimer()
            }
            pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
        }
    }

    /// Hides the panel once the mouse has been outside both the Dock icon
    /// and the panel (plus the gap between them) for a short moment.
    private func startHoverTimer() {
        hoverTimer?.invalidate()
        outsideSince = nil
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            guard preview.isVisible else { t.invalidate(); return }
            preview.trackMouse(NSEvent.mouseLocation)
            let safeZone = preview.frame.union(preview.anchorFrame).insetBy(dx: -8, dy: -8)
            if safeZone.contains(NSEvent.mouseLocation) {
                outsideSince = nil
            } else if let since = outsideSince {
                if Date().timeIntervalSince(since) > 0.25 { preview.hide(); t.invalidate() }
            } else {
                outsideSince = Date()
            }
        }
    }

    // MARK: Setup

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "DockPeek")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let ax = AXIsProcessTrusted(), sc = CGPreflightScreenCaptureAccess()
        menu.addItem(withTitle: "DockPeek চালু আছে", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Accessibility: \(ax ? "✓" : "✗ দরকার")", action: #selector(openAXSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Screen Recording: \(sc ? "✓" : "✗ দরকার")", action: #selector(openSCSettings), keyEquivalent: "")
        menu.addItem(.separator())
        let clickItem = NSMenuItem(title: "Icon চাপলে minimize / restore", action: #selector(toggleClick), keyEquivalent: "")
        clickItem.state = DockClickHandler.isEnabled ? .on : .off
        menu.addItem(clickItem)

        let speed = NSMenuItem(title: "Preview দেখানোর গতি", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for (i, choice) in Self.delayChoices.enumerated() {
            let item = NSMenuItem(title: choice.title, action: #selector(setDelay(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = abs(Self.hoverDelay - choice.seconds) < 0.01 ? .on : .off
            speedMenu.addItem(item)
        }
        speed.submenu = speedMenu
        menu.addItem(speed)
        let login = NSMenuItem(title: "Mac চালু হলে চালু হবে", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "বন্ধ করুন", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openSCSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        Self.hoverDelay = Self.delayChoices[sender.tag].seconds
    }

    @objc private func toggleClick() {
        DockClickHandler.isEnabled.toggle()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("DockPeek login item error: \(error)") }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
