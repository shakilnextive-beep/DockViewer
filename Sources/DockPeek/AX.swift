import AppKit
import ApplicationServices

// Private but long-stable API: maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func bool(_ name: String) -> Bool? { raw(name) as? Bool }
    func elements(_ name: String) -> [AXUIElement] { (raw(name) as? [AXUIElement]) ?? [] }

    func element(_ name: String) -> AXUIElement? {
        guard let v = raw(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }

    var position: CGPoint? {
        guard let v = raw(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    var size: CGSize? {
        guard let v = raw(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &s)
        return s
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    func set(_ name: String, _ value: Bool) {
        AXUIElementSetAttributeValue(self, name as CFString, value as CFBoolean)
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }
}

/// Converts an Accessibility rect (top-left origin of the primary screen)
/// to a Cocoa rect (bottom-left origin).
func cocoaRect(fromAX origin: CGPoint, size: CGSize) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: origin.x, y: primaryHeight - origin.y - size.height, width: size.width, height: size.height)
}
