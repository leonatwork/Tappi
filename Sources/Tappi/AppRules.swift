import CoreGraphics

/// Bundle IDs are normalized when settings or foreground apps change, never
/// inside the tap. Its only app lookup is membership in an already-built set.
enum AppRules {
    static func normalizedBundleID(_ bundleID: String?) -> String? {
        bundleID?.lowercased()
    }

    static func normalized(_ bundleIDs: [String]) -> Set<String> {
        Set(bundleIDs.map { $0.lowercased() })
    }

    static func isPassthrough(frontmostBundleID: String?, passthroughBundleIDs: Set<String>) -> Bool {
        guard let frontmostBundleID else { return false }
        return passthroughBundleIDs.contains(frontmostBundleID)
    }

    static func shouldHandleKeyDown(keyCode: Int64, flags: CGEventFlags,
                                    modifier: HoldModifier, sessionActive: Bool,
                                    frontmostBundleID: String?, passthroughBundleIDs: Set<String>) -> Bool {
        // An activation during cycling must not strand a holding or sticky session.
        if sessionActive { return true }
        return flags.contains(modifier.flag)
            && (keyCode == KeyCode.tab || KeyCode.aboveTab.contains(keyCode))
            && !isPassthrough(frontmostBundleID: frontmostBundleID,
                              passthroughBundleIDs: passthroughBundleIDs)
    }
}
