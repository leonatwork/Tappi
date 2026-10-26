import CoreGraphics

/// Rebuilt when settings change, never in the tap. Foreground IDs are normalized
/// when cached, so deciding whether to pass a hotkey through is one Set lookup.
struct AppExclusionPolicy {
    private let excludedBundleIDs: Set<String>
    private let passthroughBundleIDs: Set<String>

    init(settings: Settings) {
        excludedBundleIDs = Set(settings.excludedApps.map { $0.lowercased() })
        passthroughBundleIDs = Set(settings.passthroughApps.map { $0.lowercased() })
    }

    static func normalize(_ bundleID: String?) -> String? { bundleID?.lowercased() }

    func excludes(bundleID: String?) -> Bool {
        guard let bundleID = Self.normalize(bundleID) else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    /// Accepts the already-normalized foreground cache, not a live app query.
    func passesThrough(frontBundleID: String?) -> Bool {
        guard let frontBundleID else { return false }
        return passthroughBundleIDs.contains(frontBundleID)
    }

    func shouldHandleKeyDown(_ keyCode: Int64, flags: CGEventFlags, modifier: HoldModifier,
                             sessionActive: Bool, frontBundleID: String?) -> Bool {
        // A foreground change must not strand a session that already owns input.
        if sessionActive { return true }
        guard flags.contains(modifier.flag), keyCode == KeyCode.tab || KeyCode.aboveTab.contains(keyCode)
        else { return false }
        return !passesThrough(frontBundleID: frontBundleID)
    }

    func shouldSuppressSystemSwitcher(settings: Settings, ready: Bool, frontBundleID: String?) -> Bool {
        settings.holdModifier == .command && settings.replaceSystemSwitcher && ready
            && !passesThrough(frontBundleID: frontBundleID)
    }
}
