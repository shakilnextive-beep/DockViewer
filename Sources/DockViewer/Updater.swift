import AppKit

/// Keeps Dock Viewer up to date from GitHub Releases.
///
/// Publishing a new GitHub release (tag `vX.Y.Z`, asset `DockViewer.zip`) is
/// all it takes: every installed copy checks on launch and every 6 hours,
/// downloads the newer build, swaps itself in place and relaunches.
/// Because the code signature is pinned to the bundle id, the user's
/// Accessibility / Screen Recording permissions carry over.
final class Updater {
    static let shared = Updater()

    static var autoInstall: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate") }
    }

    private var timer: Timer?
    private var busy = false

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    // MARK: Checking

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let assets: [Asset]
    }

    func check(userInitiated: Bool) {
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DockViewer/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    self.busy = false
                    Log.write("update: check failed \(error?.localizedDescription ?? "bad response")")
                    if userInitiated { self.alert("Couldn't check for updates", "Check your internet connection and try again.") }
                    return
                }
                let remote = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Self.isNewer(remote, than: AppInfo.version),
                      let asset = release.assets.first(where: { $0.name == AppInfo.updateAssetName }) else {
                    self.busy = false
                    if userInitiated { self.alert("You're up to date", "\(AppInfo.name) \(AppInfo.version) is the latest version.") }
                    return
                }
                Log.write("update: \(AppInfo.version) → \(remote) available")
                if userInitiated || Self.autoInstall {
                    self.install(from: asset.browser_download_url, version: remote)
                } else {
                    self.busy = false
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installing

    private func install(from url: URL, version: String) {
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, error in
            guard let self else { return }
            guard let tmp else {
                Log.write("update: download failed \(error?.localizedDescription ?? "")")
                DispatchQueue.main.async { self.busy = false }
                return
            }
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("DockViewerUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

                guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }),
                      Bundle(url: newApp)?.bundleIdentifier == AppInfo.bundleID
                else { throw NSError(domain: "update", code: 1, userInfo: [NSLocalizedDescriptionKey: "no valid app in zip"]) }
                _ = try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

                DispatchQueue.main.async { self.swapAndRelaunch(newApp: newApp, version: version) }
            } catch {
                Log.write("update: install failed \(error.localizedDescription)")
                DispatchQueue.main.async { self.busy = false }
            }
        }.resume()
    }

    /// A tiny shell helper waits for us to quit, replaces the app, reopens it.
    private func swapAndRelaunch(newApp: URL, version: String) {
        let target = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target)"
        mv "\(newApp.path)" "\(target)"
        open "\(target)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        do {
            try p.run()
            Log.write("update: installing \(version) and relaunching")
            NSApp.terminate(nil)
        } catch {
            Log.write("update: could not start installer \(error.localizedDescription)")
            busy = false
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
