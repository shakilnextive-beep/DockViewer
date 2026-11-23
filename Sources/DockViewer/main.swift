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
        enableLoginItemByDefault()
        Updater.shared.start()

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
        ("Fast (0.2 s)", 0.2), ("Normal (0.4 s)", 0.4), ("Relaxed (0.7 s)", 0.7),
    ]
    static var hoverDelay: Double {
        get { UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.4 }
        set { UserDefaults.standard.set(newValue, forKey: "hoverDelay") }
    }

    private func dockHoverChanged(_ item: DockItem?) {
        pendingShow?.cancel()
        guard let item else { return }   // mouse left an icon; the hover timer decides when to hide
        guard let app = WindowManager.shared.runningApp(for: item.appURL) else {
            return
        }
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
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: AppInfo.name)
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let ax = AXIsProcessTrusted(), sc = CGPreflightScreenCaptureAccess()
        let header = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(withTitle: "Accessibility: \(ax ? "✓ Allowed" : "✗ Needed — click to fix")", action: #selector(openAXSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Screen Recording: \(sc ? "✓ Allowed" : "✗ Needed — click to fix")", action: #selector(openSCSettings), keyEquivalent: "")
        menu.addItem(.separator())
        let clickItem = NSMenuItem(title: "Click Dock Icon to Minimize / Restore", action: #selector(toggleClick), keyEquivalent: "")
        clickItem.state = DockClickHandler.isEnabled ? .on : .off
        menu.addItem(clickItem)

        let speed = NSMenuItem(title: "Preview Speed", action: nil, keyEquivalent: "")
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
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let auto = NSMenuItem(title: "Install Updates Automatically", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        auto.state = Updater.autoInstall ? .on : .off
        menu.addItem(auto)
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Share \(AppInfo.name)…", action: #selector(share), keyEquivalent: "")
        menu.addItem(withTitle: "Visit SupportKori", action: #selector(openWebsite), keyEquivalent: "")
        menu.addItem(withTitle: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func toggleAutoUpdate() { Updater.autoInstall.toggle() }

    @objc private func checkForUpdates() { Updater.shared.check(userInitiated: true) }

    @objc private func openWebsite() { NSWorkspace.shared.open(AppInfo.websiteURL) }

    @objc private func share() {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            let text = "\(AppInfo.name) — free Windows-style window and tab previews for the Mac Dock"
            NSSharingServicePicker(items: [text, AppInfo.shareURL])
                .show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        func link(_ title: String, _ url: URL) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [.link: url, .font: NSFont.systemFont(ofSize: 11)])
        }
        credits.append(NSAttributedString(string: "Windows-style window and browser-tab previews for the macOS Dock.\n\nMade by ", attributes: body))
        credits.append(link(AppInfo.creditName, AppInfo.creditURL))
        credits.append(NSAttributedString(string: "\nGet it free on ", attributes: body))
        credits.append(link("SupportKori", AppInfo.shareURL))
        credits.append(NSAttributedString(string: " · Source on ", attributes: body))
        credits.append(link("GitHub", AppInfo.githubURL))
        credits.append(NSAttributedString(string: "\n\nFree to use and share. Not for sale.", attributes: body))
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: credits,
        ])
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        Self.hoverDelay = Self.delayChoices[sender.tag].seconds
    }

    @objc private func toggleClick() {
        DockClickHandler.isEnabled.toggle()
    }

    @objc private func toggleLogin() {
        UserDefaults.standard.set(true, forKey: "loginChoiceMade")
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { Log.write("login item error: \(error.localizedDescription)") }
        Log.write("login item status: \(Self.loginStatusText)")
    }

    /// Turn "start at login" on by default the first time Dock Viewer runs,
    /// unless the user has already switched it off from the menu.
    private func enableLoginItemByDefault() {
        if !UserDefaults.standard.bool(forKey: "loginChoiceMade"), SMAppService.mainApp.status != .enabled {
            do { try SMAppService.mainApp.register() }
            catch { Log.write("login item error: \(error.localizedDescription)") }
        }
        Log.write("login item status: \(Self.loginStatusText)")
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private static var loginStatusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "needs approval in System Settings → General → Login Items"
        case .notRegistered: return "not registered"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
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
