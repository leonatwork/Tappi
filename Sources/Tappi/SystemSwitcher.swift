import AppKit
import CoreGraphics

/// Turns macOS' own ⌘Tab switcher off while Tappi owns that shortcut.
///
/// ⌘Tab is not an ordinary keystroke: the window server handles it as a
/// "symbolic hot key" before any session event tap ever sees it. Swallowing the
/// key in our tap is therefore not enough — the system switcher still appears in
/// front of ours. The only reliable way to take the shortcut over is to disable
/// the symbolic hot key itself.
///
/// This uses a private CoreGraphics Services API — the same one AltTab relies on,
/// because macOS exposes no public equivalent.
enum SystemSwitcher {
    /// Symbolic hot key identifiers, as used by the window server.
    private enum HotKey: UInt32, CaseIterable {
        case commandTab = 1          // Move focus to next application
        case commandShiftTab = 2     // Move focus to previous application
        case commandAboveTab = 27    // Move focus to next window in application (⌘`)
        case commandShiftAboveTab = 28
    }

    /// The disabled state persists after we exit, so this must always be undone.
    private static var disabledByUs = false

    static var isSuppressed: Bool { disabledByUs }

    /// True when every shortcut we care about is currently enabled system-wide.
    static var systemShortcutsEnabled: Bool {
        HotKey.allCases.allSatisfy { CGSIsSymbolicHotKeyEnabled($0.rawValue) }
    }

    private static func suppress() {
        guard !disabledByUs else { return }
        for key in HotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(key.rawValue, false)
        }
        disabledByUs = true
        NSLog("Tappi: system ⌘Tab switcher disabled")
    }

    /// Hand the shortcuts back. Safe to call repeatedly and when we never disabled
    /// anything — a previous hard kill can leave the system without a switcher, and
    /// calling this unconditionally at launch repairs exactly that.
    static func restore(force: Bool = false) {
        guard force || disabledByUs else { return }
        for key in HotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(key.rawValue, true)
        }
        if disabledByUs { NSLog("Tappi: system ⌘Tab switcher restored") }
        disabledByUs = false
    }

    /// Repairs the one state nobody should ever be left in: the system switcher
    /// disabled by a previous run that was killed before it could hand it back.
    static func repairOrphanedState() {
        if !systemShortcutsEnabled { restore(force: true) }
    }

    /// Match the system state to the settings *and* to whether Tappi can actually
    /// do the job.
    ///
    /// Taking ⌘Tab away is only defensible while we can genuinely replace it. If
    /// Accessibility is missing or revoked — which macOS signals by quietly
    /// returning nothing rather than by failing — suppressing the system switcher
    /// would leave the machine with no switcher at all. So readiness is checked on
    /// every window-list update, and the shortcut goes straight back the moment we
    /// cannot serve it.
    static func apply() {
        let settings = SettingsStore.shared.value
        let ready = AX.isTrusted
            && SwitcherController.shared.isRunning
            && WindowStore.shared.isOperational
        if settings.holdModifier == .command && settings.replaceSystemSwitcher && ready {
            suppress()
        } else {
            restore()
        }
    }
}

// MARK: - Private CoreGraphics Services

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: UInt32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
private func CGSIsSymbolicHotKeyEnabled(_ hotKey: UInt32) -> Bool
