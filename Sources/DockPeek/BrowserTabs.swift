import AppKit

struct TabInfo: Identifiable {
    let id: Int                 // position in the list (stable for one load)
    let windowID: String        // the browser's own AppleScript window id
    let windowOrigin: CGPoint   // top-left, same space as Accessibility positions
    let windowNumber: Int       // 1, 2, … for section labels
    let index: Int              // 1-based tab index inside its window
    let active: Bool
    let key: String             // cache key for the tab's picture
    let title: String
    let url: String
    var image: CGImage?

    var host: String {
        guard let h = URL(string: url)?.host else { return url.isEmpty ? "New Tab" : url }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

/// Reads and controls browser tabs through AppleScript.
/// Chromium browsers (Chrome, Opera, Edge, Brave, Vivaldi, Arc) share one
/// scripting dictionary; Safari has its own. Firefox has none.
final class BrowserTabs {
    static let shared = BrowserTabs()

    enum Kind { case chromium, safari }

    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
    ]

    /// Last seen picture of every tab, so background tabs keep an image.
    private var imageCache: [String: CGImage] = [:]
    private let queue = DispatchQueue(label: "dockpeek.applescript")
    private static let US = "\u{1F}", RS = "\u{1E}"

    func kind(of app: NSRunningApplication) -> Kind? {
        guard let id = app.bundleIdentifier else { return nil }
        if Self.chromium.contains(id) { return .chromium }
        if id == "com.apple.Safari" { return .safari }
        return nil
    }

    // MARK: Reading tabs

    /// Loads all tabs off the main thread; calls back on main.
    func loadTabs(for app: NSRunningApplication, completion: @escaping ([TabInfo]) -> Void) {
        guard let kind = kind(of: app), let bundle = app.bundleIdentifier else { return completion([]) }
        let source = kind == .chromium ? Self.chromiumListScript(bundle) : Self.safariListScript(bundle)
        queue.async {
            let text = Self.run(source) ?? ""
            let tabs = Self.parse(text, bundle: bundle)
            DispatchQueue.main.async {
                completion(tabs.map { t in var t = t; t.image = self.imageCache[t.key]; return t })
            }
        }
    }

    private static func chromiumListScript(_ bundle: String) -> String {
        """
        set US to character id 31
        set RS to character id 30
        set out to ""
        tell application id "\(bundle)"
            repeat with w in windows
                try
                    set b to bounds of w
                    set wid to (id of w) as text
                    set ai to active tab index of w
                    set ids to id of tabs of w
                    set ts to title of tabs of w
                    set us_ to URL of tabs of w
                    repeat with i from 1 to count of ids
                        set out to out & wid & US & (item 1 of b) & US & (item 2 of b) & US & i & US & (i = ai) & US & (item i of ids) & US & (item i of ts) & US & (item i of us_) & RS
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    private static func safariListScript(_ bundle: String) -> String {
        """
        set US to character id 31
        set RS to character id 30
        set out to ""
        tell application id "\(bundle)"
            repeat with w in windows
                try
                    set b to bounds of w
                    set wid to (id of w) as text
                    set ci to index of current tab of w
                    set ts to name of tabs of w
                    set us_ to URL of tabs of w
                    repeat with i from 1 to count of ts
                        set u to item i of us_
                        if u is missing value then set u to ""
                        set out to out & wid & US & (item 1 of b) & US & (item 2 of b) & US & i & US & (i = ci) & US & (wid & "-" & u) & US & (item i of ts) & US & u & RS
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    private static func parse(_ text: String, bundle: String) -> [TabInfo] {
        var tabs: [TabInfo] = []
        var windowNumbers: [String: Int] = [:]
        for row in text.components(separatedBy: RS) where !row.isEmpty {
            let f = row.components(separatedBy: US)
            guard f.count >= 8, let x = Double(f[1]), let y = Double(f[2]), let index = Int(f[3]) else { continue }
            let wid = f[0]
            if windowNumbers[wid] == nil { windowNumbers[wid] = windowNumbers.count + 1 }
            tabs.append(TabInfo(id: tabs.count, windowID: wid, windowOrigin: CGPoint(x: x, y: y),
                                windowNumber: windowNumbers[wid]!, index: index, active: f[4] == "true",
                                key: "\(bundle):\(f[5])", title: f[6].isEmpty ? f[7] : f[6],
                                url: f[7], image: nil))
        }
        return tabs
    }

    // MARK: Actions

    func select(_ tab: TabInfo, in app: NSRunningApplication) {
        guard let kind = kind(of: app), let bundle = app.bundleIdentifier else { return }
        let w = kind == .chromium ? "window id \(tab.windowID)" : "(first window whose id is \(tab.windowID))"
        let pick = kind == .chromium
            ? "set active tab index of w to \(tab.index)"
            : "set current tab of w to tab \(tab.index) of w"
        let source = """
        tell application id "\(bundle)"
            set w to \(w)
            try
                set minimized of w to false
            end try
            \(pick)
            set index of w to 1
            activate
        end tell
        """
        queue.async { _ = Self.run(source) }
    }

    func close(_ tab: TabInfo, in app: NSRunningApplication, then done: @escaping () -> Void) {
        guard let kind = kind(of: app), let bundle = app.bundleIdentifier else { return }
        let w = kind == .chromium ? "window id \(tab.windowID)" : "(first window whose id is \(tab.windowID))"
        let source = """
        tell application id "\(bundle)"
            close tab \(tab.index) of \(w)
        end tell
        """
        imageCache[tab.key] = nil
        queue.async {
            _ = Self.run(source)
            DispatchQueue.main.async(execute: done)
        }
    }

    // MARK: Capture every tab

    private(set) var isCapturing = false

    /// Switches through every tab of every visible window, photographs it,
    /// then puts each window back on the tab it was showing. The browser
    /// does not need to be in front.
    @MainActor
    func captureAll(app: NSRunningApplication, tabs: [TabInfo],
                    progress: @escaping (_ done: Int, _ total: Int, _ tab: TabInfo, _ image: CGImage?) -> Void) async {
        guard !isCapturing, let kind = kind(of: app), let bundle = app.bundleIdentifier else { return }
        isCapturing = true
        defer { isCapturing = false }

        let windows = WindowManager.shared.windows(for: app).filter { !$0.minimized }
        func cgWindow(for tab: TabInfo) -> CGWindowID? {
            windows.first { Self.sameOrigin($0.origin, tab.windowOrigin) }?.id
        }
        let todo = tabs.filter { cgWindow(for: $0) != nil }
        let originalActive = tabs.filter(\.active)
        Log.write("capture-all: \(todo.count) tab(s) in \(app.localizedName ?? "?")")

        for (n, tab) in todo.enumerated() {
            guard let wid = cgWindow(for: tab) else { continue }
            await runAsync(Self.switchScript(kind, bundle, tab))
            try? await Task.sleep(nanoseconds: 550_000_000)        // let the page paint
            let image = await WindowManager.shared.captureWindow(wid)
            if let image { imageCache[tab.key] = image }
            progress(n + 1, todo.count, tab, image)
        }
        for tab in originalActive { await runAsync(Self.switchScript(kind, bundle, tab)) }
    }

    private static func switchScript(_ kind: Kind, _ bundle: String, _ tab: TabInfo) -> String {
        kind == .chromium
            ? "tell application id \"\(bundle)\" to set active tab index of window id \(tab.windowID) to \(tab.index)"
            : """
              tell application id "\(bundle)"
                  set w to (first window whose id is \(tab.windowID))
                  set current tab of w to tab \(tab.index) of w
              end tell
              """
    }

    private func runAsync(_ source: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { _ = Self.run(source); c.resume() }
        }
    }

    // MARK: Tab pictures

    /// A browser window's screenshot shows its active tab: store it under
    /// that tab, so the tab keeps a picture after you switch away from it.
    func remember(windowImages: [CGWindowID: CGImage], windows: [WindowInfo], tabs: [TabInfo]) {
        for w in windows {
            guard let image = windowImages[w.id],
                  let tab = tabs.first(where: { $0.active && Self.sameOrigin($0.windowOrigin, w.origin) })
            else { continue }
            imageCache[tab.key] = image
        }
    }

    /// Called every few seconds for the frontmost app.
    func warmCache(for app: NSRunningApplication, windows: [WindowInfo], images: [CGWindowID: CGImage]) {
        guard kind(of: app) != nil, !images.isEmpty else { return }
        loadTabs(for: app) { [weak self] tabs in
            self?.remember(windowImages: images, windows: windows, tabs: tabs)
        }
    }

    private static func sameOrigin(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 3 && abs(a.y - b.y) < 3
    }

    // MARK: AppleScript

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.write("applescript error: \(error[NSAppleScript.errorMessage] ?? error)")
            return nil
        }
        return result?.stringValue
    }
}
