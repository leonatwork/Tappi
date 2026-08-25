import AppKit
import CoreGraphics

enum KeyCode {
    static let tab: Int64 = 48
    static let escape: Int64 = 53

    /// The key directly above Tab — "⌘ plus the key above Tab" is what macOS and
    /// Windows both use for "next window in this app".
    ///
    /// Which keycode that is depends on the physical keyboard, and the two are
    /// swapped between layouts: ANSI boards put `grave` (50) above Tab, while ISO
    /// boards — German included — report 10 there and move 50 to the extra key
    /// beside the left shift. Accepting both makes the shortcut land on the key
    /// the user is actually looking at, whatever they are typing on.
    static let aboveTab: Set<Int64> = [50, 10]
    static let ret: Int64 = 36
    static let space: Int64 = 49
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
    static let w: Int64 = 13
    static let q: Int64 = 12
}

protocol EventTapDelegate: AnyObject {
    /// Return `true` to swallow the event so it never reaches the focused app.
    func eventTap(keyDown keyCode: Int64, flags: CGEventFlags) -> Bool
    func eventTap(flagsChanged keyCode: Int64, flags: CGEventFlags) -> Bool
}

/// A session-level tap that sees keystrokes before the focused application does.
///
/// The callback runs on the main run loop and must stay fast — if it blocks, the
/// system disables the tap. Everything it triggers is O(1) work against an
/// already-warm window list.
final class EventTap {
    /// Set TAPPI_DEBUG=1 to trace every key event the tap sees.
    static let debug = ProcessInfo.processInfo.environment["TAPPI_DEBUG"] == "1"

    weak var delegate: EventTapDelegate?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isEnabled: Bool { tap != nil }

    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that took too long; just switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let delegate else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let swallow: Bool
        switch type {
        case .keyDown:
            swallow = delegate.eventTap(keyDown: keyCode, flags: flags)
        case .flagsChanged:
            swallow = delegate.eventTap(flagsChanged: keyCode, flags: flags)
        default:
            swallow = false
        }
        if EventTap.debug {
            NSLog("Tappi/tap: type=%d key=%d flags=%llx swallow=%@",
                  type.rawValue, keyCode, flags.rawValue, swallow ? "yes" : "no")
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}
