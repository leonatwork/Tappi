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
    private static var ownsLifecycle = false

    /// Only a copy admitted by the single-instance gate may change global state.
    static func claimOwnership() { ownsLifecycle = true }

    static func relinquishOwnership() {
        restore()
        ownsLifecycle = false
    }

    static var isSuppressed: Bool { disabledByUs }

    /// True when every shortcut we care about is currently enabled system-wide.
    static var systemShortcutsEnabled: Bool {
        HotKey.allCases.allSatisfy { CGSIsSymbolicHotKeyEnabled($0.rawValue) }
    }

    private static func suppress() {
        guard ownsLifecycle, !disabledByUs else { return }
        for key in HotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(key.rawValue, false)
        }
        disabledByUs = true
        NSLog("Tappi: system ⌘Tab switcher disabled")
    }

    /// Force permits explicit repair by the admitted instance, never by a rejected
    /// second copy. Ordinary shutdown restores only suppression owned by this run.
    static func restore(force: Bool = false) {
        guard InstanceLifecycle.shouldRestore(ownsLifecycle: ownsLifecycle,
                                               suppressedByUs: disabledByUs, force: force) else { return }
        for key in HotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(key.rawValue, true)
        }
        if disabledByUs { NSLog("Tappi: system ⌘Tab switcher restored") }
        disabledByUs = false
    }

    /// Repairs the one state nobody should ever be left in: the system switcher
    /// disabled by a previous run that was killed before it could hand it back.
    static func repairOrphanedState() {
        guard ownsLifecycle else { return }
        if !systemShortcutsEnabled { restore(force: true) }
    }

    /// Match the system state to the settings *and* to whether Tappi can actually
    /// do the job.
    ///
    /// Taking ⌘Tab away is only defensible while we can genuinely replace it. If
    /// Accessibility is missing or revoked — which macOS signals by quietly
    /// returning nothing rather than by failing — suppressing the system switcher
    /// would leave the machine with no switcher at all. So readiness is checked on
    /// every window-list update and app activation. A passthrough app gets the
    /// shortcut back immediately, without waiting for its AX queries to finish.
    static func apply() {
        guard ownsLifecycle else { return }
        let settings = SettingsStore.shared.value
        let ready = AX.isTrusted
            && SwitcherController.shared.isRunning
            && WindowStore.shared.isOperational
        if SettingsStore.shared.appExclusionPolicy.shouldSuppressSystemSwitcher(
            settings: settings, ready: ready, frontBundleID: WindowStore.shared.frontmostBundleID) {
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
