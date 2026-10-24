import AppKit
import ApplicationServices

/// The single source of truth for "which windows exist, in which order".
///
/// The whole point of this type is that it is *always warm*: the list, the
/// titles and the icons are maintained continuously in the background, driven by
/// Accessibility notifications, so pressing the hotkey costs a plain array read
/// instead of a round of IPC.
final class WindowStore {
    static let shared = WindowStore()

    /// Windows in most-recently-used order. Index 0 is the current window.
    private(set) var entries: [WindowEntry] = []

    /// Main-run-loop cache shared by the tap and the system-shortcut policy.
    /// The bundle ID is already lowercase, so the tap does no normalization.
    private(set) var frontmostBundleID: String?
    private(set) var frontmostPID: pid_t?

    /// Whether we are actually seeing windows.
    ///
    /// Worth having as a separate signal because a missing Accessibility grant
    /// does not surface as an error: `AXIsProcessTrusted()` still reports `true`
    /// for a process launched from a trusted parent, and the window queries simply
    /// come back degraded. An empty list despite running apps is the real symptom.
    var isOperational: Bool { !entries.isEmpty }

    private let queue = DispatchQueue(label: "de.tappi.windowstore", qos: .userInitiated)
    private var observers: [pid_t: AXObserver] = [:]
    private var refreshScheduled = false
    private var sweepTimer: Timer?
    private var seeded = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged(_:)),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        cacheFrontmostApplication(NSWorkspace.shared.frontmostApplication)
        for app in regularApps() { attachObserver(app.processIdentifier) }
        refresh()

        // Safety net for windows that disappear without emitting a notification.
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        sweepTimer?.tolerance = 1.0
    }

    // MARK: - Ordering

    /// Move an entry to the front of the MRU list.
    func promote(_ entry: WindowEntry) {
        guard let index = entries.firstIndex(where: { $0 === entry }), index != 0 else { return }
        entries.remove(at: index)
        entries.insert(entry, at: 0)
    }

    func promote(element: AXUIElement) {
        guard let entry = entries.first(where: { $0.matches(element) }) else {
            refresh()
            return
        }
        promote(entry)
    }

    /// The list a switching session operates on, after applying the user's filters.
    func sessionList(scope: SwitchScope) -> [WindowEntry] {
        let store = SettingsStore.shared
        return Self.sessionList(entries: entries, scope: scope, settings: store.value,
                                frontPid: frontmostPID, excludedBundleIDs: store.excludedBundleIDs)
    }

    /// Pure filtering leaves the backing entries and their order untouched.
    static func sessionList(entries: [WindowEntry], scope: SwitchScope, settings: Settings,
                            frontPid: pid_t?, excludedBundleIDs: Set<String>) -> [WindowEntry] {
        return entries.filter { entry in
            if let bundleID = entry.bundleID, excludedBundleIDs.contains(bundleID.lowercased()) { return false }
            if scope == .currentApp && entry.pid != frontPid { return false }
            if entry.isMinimized && !settings.includeMinimized { return false }
            if entry.isHidden && !settings.includeHiddenApps { return false }
            if !entry.isOnActiveSpace && !entry.isMinimized && !settings.includeOtherSpaces { return false }
            return true
        }
    }

    // MARK: - Refresh

    /// Coalesced, always-off-the-main-thread rebuild of the window list.
    func refresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.performRefresh()
        }
    }

    private struct AppSnapshot {
        let pid: pid_t
        let name: String
        let bundleID: String?
        let icon: NSImage?
        let isHidden: Bool
    }

    private struct RawWindow {
        let axWindow: AXUIElement
        let app: AppSnapshot
        let title: String
        let isMinimized: Bool
        let frame: CGRect?
        var cgWindowID: CGWindowID?
        var zIndex: Int
        var isOnActiveSpace: Bool
    }

    private struct WindowKey: Equatable {
        let element: AXUIElement

        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }
    }

    private func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    private func performRefresh() {
        // Touch AppKit only on the main thread; the slow AX round-trips happen after.
        let snapshots = regularApps().map {
            AppSnapshot(pid: $0.processIdentifier, name: $0.localizedName ?? "",
                        bundleID: $0.bundleIdentifier, icon: $0.icon, isHidden: $0.isHidden)
        }
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.enumerate(snapshots)
            let focused = frontPid.flatMap { AX.element(AX.application($0), kAXFocusedWindowAttribute) }
            DispatchQueue.main.async {
                self.merge(snapshot.windows, unresponsivePIDs: snapshot.unresponsivePIDs, focused: focused)
            }
        }
    }

    /// CoreGraphics knows the true z-order and which windows are on the current
    /// Space; Accessibility knows the titles. We join them on (pid, frame).
    private func enumerate(_ apps: [AppSnapshot]) -> (windows: [RawWindow], unresponsivePIDs: Set<pid_t>) {
        var onScreen: [pid_t: [(id: CGWindowID, rect: CGRect, z: Int)]] = [:]
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for (index, info) in list.enumerated() {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      let id = info[kCGWindowNumber as String] as? CGWindowID,
                      let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
                else { continue }
                onScreen[pid, default: []].append((id, rect, index))
            }
        }

        var result: [RawWindow] = []
        var unresponsivePIDs: Set<pid_t> = []
        for app in apps {
            let axApp = AX.application(app.pid)
            guard let windows = AX.windows(axApp) else {
                unresponsivePIDs.insert(app.pid)
                continue
            }
            var candidates = onScreen[app.pid] ?? []
            for window in windows {
                let minimized = AX.bool(window, kAXMinimizedAttribute) ?? false
                guard AX.isSwitchable(window, minimized: minimized) else { continue }
                let title = AX.string(window, kAXTitleAttribute) ?? ""
                let frame = AX.frame(window)

                var cgID: CGWindowID?
                var zIndex = Int.max
                var onActiveSpace = false
                if !minimized, let frame,
                   let matchIndex = candidates.firstIndex(where: { close($0.rect, frame) }) {
                    let match = candidates.remove(at: matchIndex)
                    cgID = match.id
                    zIndex = match.z
                    onActiveSpace = true
                }

                result.append(RawWindow(axWindow: window, app: app, title: title,
                                        isMinimized: minimized, frame: frame,
                                        cgWindowID: cgID, zIndex: zIndex,
                                        isOnActiveSpace: onActiveSpace))
            }
        }
        return (result, unresponsivePIDs)
    }

    private func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Apply the pure ordering result without replacing existing entries and
    /// their cached thumbnails. A missing fresh value leaves all last values intact.
    private func merge(_ raw: [RawWindow], unresponsivePIDs: Set<pid_t>, focused: AXUIElement?) {
        // An app may terminate while the background AX queries are in flight.
        let runningPIDs = Set(regularApps().map(\.processIdentifier))
        typealias Item = WindowMergeItem<WindowKey, pid_t, RawWindow?>
        let previousEntries = entries
        let old = previousEntries.map {
            Item(key: WindowKey(element: $0.axWindow), pid: $0.pid, zIndex: Int.max, value: nil)
        }
        let snapshot = raw.filter { runningPIDs.contains($0.app.pid) }.map {
            Item(key: WindowKey(element: $0.axWindow), pid: $0.app.pid, zIndex: $0.zIndex, value: $0)
        }
        let merged = WindowMerge.merge(old: old, snapshot: snapshot,
                                       unresponsivePIDs: unresponsivePIDs.intersection(runningPIDs),
                                       seeded: seeded)
        entries = merged.compactMap { item -> WindowEntry? in
            let existing = previousEntries.first { $0.pid == item.pid && $0.matches(item.key.element) }
            guard let fresh = item.value else { return existing }
            guard let entry = existing else {
                return WindowEntry(axWindow: fresh.axWindow, pid: fresh.app.pid, title: fresh.title,
                                   appName: fresh.app.name, icon: fresh.app.icon,
                                   isMinimized: fresh.isMinimized, isHidden: fresh.app.isHidden,
                                   isOnActiveSpace: fresh.isOnActiveSpace, frame: fresh.frame,
                                   cgWindowID: fresh.cgWindowID, bundleID: fresh.app.bundleID)
            }
            entry.title = fresh.title
            entry.appName = fresh.app.name
            entry.bundleID = fresh.app.bundleID
            entry.icon = fresh.app.icon
            entry.isMinimized = fresh.isMinimized
            entry.isHidden = fresh.app.isHidden
            entry.isOnActiveSpace = fresh.isOnActiveSpace
            entry.frame = fresh.frame
            if let id = fresh.cgWindowID, id != entry.cgWindowID {
                entry.cgWindowID = id
                entry.thumbnail = nil
            }
            return entry
        }
        if !seeded { seeded = !entries.isEmpty }

        // Keep index 0 in sync with what the user is actually looking at.
        if let focused, let entry = entries.first(where: { $0.matches(focused) }) {
            promote(entry)
        }
        // Readiness may have just changed in either direction.
        SystemSwitcher.apply()
        NotificationCenter.default.post(name: WindowStore.didChange, object: nil)
    }

    static let didChange = Notification.Name("TappiWindowStoreDidChange")


    // MARK: - Notifications

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Apps are not ready to answer AX queries the instant they launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.attachObserver(app.processIdentifier)
            self?.refresh()
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        observers.removeValue(forKey: pid)
        entries.removeAll { $0.pid == pid }
        refresh()
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Release/reclaim symbolic hot keys immediately, before any AX work.
        cacheFrontmostApplication(app)
        SystemSwitcher.apply()
        attachObserver(app.processIdentifier)
        let pid = app.processIdentifier
        queue.async { [weak self] in
            let focused = AX.element(AX.application(pid), kAXFocusedWindowAttribute)
            DispatchQueue.main.async {
                guard let self else { return }
                if let focused { self.promote(element: focused) } else { self.refresh() }
            }
        }
    }

    private func cacheFrontmostApplication(_ app: NSRunningApplication?) {
        frontmostPID = app?.processIdentifier
        frontmostBundleID = AppRules.normalizedBundleID(app?.bundleIdentifier)
    }

    @objc private func spaceChanged(_ note: Notification) {
        refresh()
    }

    private func attachObserver(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let store = Unmanaged<WindowStore>.fromOpaque(refcon).takeUnretainedValue()
            store.handle(notification as String, element: element)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let axApp = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
            kAXTitleChangedNotification, kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
        ]
        for name in notifications {
            AXObserverAddNotification(observer, axApp, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func handle(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            promote(element: element)
        case kAXTitleChangedNotification:
            if let entry = entries.first(where: { $0.matches(element) }) {
                entry.title = AX.string(element, kAXTitleAttribute) ?? entry.title
                NotificationCenter.default.post(name: WindowStore.didChange, object: nil)
            } else {
                refresh()
            }
        default:
            refresh()
        }
    }
}
