/// The filter needs only cached window facts, never Accessibility or AppKit.
protocol SessionWindow {
    var pid: Int32 { get }
    var bundleID: String? { get }
    var isMinimized: Bool { get }
    var isHidden: Bool { get }
    var isOnActiveSpace: Bool { get }
}

enum WindowSessionList {
    static func make<Entry: SessionWindow>(entries: [Entry], settings: Settings,
                                           scope: SwitchScope, frontPid: Int32?,
                                           policy: AppExclusionPolicy? = nil) -> [Entry] {
        let policy = policy ?? AppExclusionPolicy(settings: settings)
        return entries.filter { entry in
            if policy.excludes(bundleID: entry.bundleID) { return false }
            if scope == .currentApp && entry.pid != frontPid { return false }
            if entry.isMinimized && !settings.includeMinimized { return false }
            if entry.isHidden && !settings.includeHiddenApps { return false }
            // Minimized windows have no on-screen match, regardless of their Space.
            if !entry.isOnActiveSpace && !entry.isMinimized && !settings.includeOtherSpaces { return false }
            return true
        }
    }
}
