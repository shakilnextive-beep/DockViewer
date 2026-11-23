import AppKit
import ApplicationServices

struct DockItem: Equatable {
    let title: String
    let appURL: URL?
    let frame: CGRect          // Cocoa coordinates
}

/// Listens to the Dock's own Accessibility tree. The Dock marks the icon
/// under the mouse as "selected", so a selection change == hover change.
final class DockWatcher {
    var onHover: ((DockItem?) -> Void)?
    /// The Dock icon currently under the mouse, if any.
    private(set) var current: DockItem?

    private var observer: AXObserver?
    private var list: AXUIElement?
    private var retryTimer: Timer?

    init() {
        // If the Dock restarts (killall Dock, settings change), reattach.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.start() }
            }
        }
    }

    func start() {
        stop()
        if !attach() {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if self?.attach() == true { t.invalidate() }
            }
        }
    }

    private func stop() {
        retryTimer?.invalidate()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        list = nil
    }

    private func attach() -> Bool {
        guard AXIsProcessTrusted() else { Log.write("attach: Accessibility NOT trusted"); return false }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { Log.write("attach: Dock not running"); return false }

        let dockAX = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = dockAX.elements(kAXChildrenAttribute).first(where: { $0.role == kAXListRole }) else {
            Log.write("attach: Dock list not found"); return false
        }

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<DockWatcher>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &obs) == .success, let obs else { return false }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, ref)
        guard err == .success else { Log.write("attach: add notification failed \(err.rawValue)"); return false }
        Log.write("attach: watching Dock OK")

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        self.list = list
        return true
    }

    private func selectionChanged() {
        guard let item = list?.elements(kAXSelectedChildrenAttribute).first,
              item.subrole == "AXApplicationDockItem",
              let pos = item.position, let size = item.size
        else { current = nil; onHover?(nil); return }

        let url = item.raw(kAXURLAttribute) as? URL
        let dockItem = DockItem(title: item.string(kAXTitleAttribute) ?? "",
                                appURL: url,
                                frame: cocoaRect(fromAX: pos, size: size))
        current = dockItem
        onHover?(dockItem)
    }
}
