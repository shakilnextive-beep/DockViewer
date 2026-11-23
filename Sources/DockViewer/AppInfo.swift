import Foundation

/// Everything public-facing about the app in one place.
enum AppInfo {
    static let name = "Dock Viewer"
    static let bundleID = "com.supportkori.dockviewer"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // Updates come from the latest GitHub release that has a DockViewer.zip asset.
    static let githubOwner = "shakilnextive-beep"
    static let githubRepo = "DockViewer"
    static let updateAssetName = "DockViewer.zip"
    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }
    static var githubURL: URL { URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")! }

    // Links shown in the app
    static let websiteURL = URL(string: "https://www.supportkori.com")!
    /// What "Share Dock Viewer…" sends. Point this at the product page once it exists.
    static let shareURL = URL(string: "https://mdshakil463.supportkori.shop")!
    static let creditName = "Creative Assistant"
    static let creditURL = URL(string: "https://www.facebook.com/profile.php?id=61596330257511")!
}
