import AppKit
import ApplicationServices

/// Windows-style taskbar clicks on the Dock:
///  • click the icon of the app you're using  → all its windows minimize
///  • click it again                          → those windows come back
///  • any other click                         → normal Dock behaviour
final class DockClickHandler {
    static let enabledKey = "minimizeOnDockClick"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var currentItem: () -> DockItem? = { nil }
    var willHandleClick: () -> Void = {}

    private var tap: CFMachPort?
    private var swallowNextMouseUp = false
    /// Windows we minimized per app, so the next click restores exactly those.
    private var minimizedByUs: [pid_t: [CGWindowID]] = [:]

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<DockClickHandler>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.write("click: could not create event tap (Accessibility?) — retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
            return
        }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("click: event tap ready")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseUp:
            if swallowNextMouseUp { swallowNextMouseUp = false; return nil }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown:
            guard Self.isEnabled, handleDockClick(at: event.location) else { return Unmanaged.passUnretained(event) }
            swallowNextMouseUp = true
            return nil   // we handled it; keep the Dock from also acting
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Returns true if the click was on a Dock icon and we acted on it.
    private func handleDockClick(at cgPoint: CGPoint) -> Bool {
        guard let item = currentItem() else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)   // to Cocoa coords
        guard item.frame.contains(point),
              let app = WindowManager.shared.runningApp(for: item.appURL) else { return false }

        let windows = WindowManager.shared.windows(for: app)
        let visible = windows.filter { !$0.minimized }
        let pid = app.processIdentifier

        // 1) App in front with open windows → minimize them all.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, !visible.isEmpty {
            willHandleClick()
            minimizedByUs[pid] = visible.map(\.id)
            visible.forEach { WindowManager.shared.minimize($0) }
            Log.write("click: minimized \(visible.count) window(s) of \(app.localizedName ?? "?")")
            return true
        }

        // 2) Windows we minimized earlier are still minimized → bring them back.
        let ours = Set(minimizedByUs[pid] ?? [])
        let toRestore = windows.filter { $0.minimized && ours.contains($0.id) }
        minimizedByUs[pid] = nil
        if !toRestore.isEmpty {
            willHandleClick()
            toRestore.forEach { WindowManager.shared.focus($0, in: app) }
            Log.write("click: restored \(toRestore.count) window(s) of \(app.localizedName ?? "?")")
            return true
        }

        // 3) Anything else → let the Dock do its normal thing (open/activate).
        return false
    }
}
