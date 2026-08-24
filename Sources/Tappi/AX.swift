import AppKit
import ApplicationServices

/// Thin, timeout-guarded wrappers around the Accessibility API.
///
/// Every call here is synchronous IPC into another process. A hung app would
/// otherwise stall us, so every application element gets a hard messaging
/// timeout and all enumeration happens off the hotkey path.
enum AX {
    /// How long we are willing to wait for any single app to answer.
    static let messagingTimeout: Float = 0.25

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that deep-links into Settings ▸ Privacy ▸ Accessibility.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String, as type: T.Type) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name, as: String.self)
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name, as: Bool.self)
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let array = raw as? [AXUIElement]
        else { return [] }
        return array
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let posValue = attribute(window, kAXPositionAttribute, as: AXValue.self),
              let sizeValue = attribute(window, kAXSizeAttribute, as: AXValue.self)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// A window worth listing: a real, standard, non-trivial window rather than a
    /// palette, sheet or utility panel.
    static func isSwitchable(_ window: AXUIElement, minimized: Bool) -> Bool {
        let subrole = string(window, kAXSubroleAttribute)
        if let subrole, subrole != kAXStandardWindowSubrole { return false }
        if subrole == nil {
            // Some apps (Electron, Java) omit the subrole. Fall back to "has a title bar".
            guard string(window, kAXRoleAttribute) == kAXWindowRole else { return false }
        }
        // Minimized windows report a zero/offscreen frame, so only size-check live ones.
        if !minimized, let f = frame(window), f.width < 40 || f.height < 40 { return false }
        return true
    }

    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized as CFTypeRef)
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func close(_ window: AXUIElement) {
        guard let button = element(window, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// True when the element still exists in its owning process.
    static func isAlive(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &raw)
        return result != .invalidUIElement && result != .cannotComplete
    }
}
