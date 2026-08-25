import AppKit
import ScreenCaptureKit

/// Live window previews — strictly additive.
///
/// This is where AltTab spends its time: it recomputes previews *while you wait*.
/// Tappi never does. The panel is drawn from icons immediately; a thumbnail is
/// captured off the main thread and faded in only if and when it arrives.
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [CGWindowID: (image: NSImage, at: CFTimeInterval)] = [:]
    private var windowsByID: [CGWindowID: SCWindow] = [:]
    private var inFlight: Set<CGWindowID> = []
    private var contentFetchedAt: CFTimeInterval = 0
    private var contentFetchInFlight = false
    private var pendingAfterFetch: [() -> Void] = []

    /// How long a captured preview is considered current.
    private let ttl: CFTimeInterval = 4.0
    /// How long the shareable-window catalogue stays valid.
    private let catalogueTTL: CFTimeInterval = 1.5

    static let didUpdate = Notification.Name("TappiThumbnailDidUpdate")

    private init() {}

    /// Cached because `CGPreflightScreenCaptureAccess()` is a synchronous trip to
    /// the TCC daemon that costs 10+ ms — calling it per window per session was
    /// single-handedly responsible for a 150 ms stall in front of the panel.
    private(set) var isGranted = false

    /// Whether access was already in place when this process started.
    ///
    /// ScreenCaptureKit only picks up a fresh grant after a restart, so a grant
    /// that arrived mid-session means "previews work after restarting", not
    /// "previews work now" — and the UI has to say which.
    private var grantedAtLaunch: Bool?

    var isAvailable: Bool {
        SettingsStore.shared.value.thumbnails && isGranted
    }

    /// Access was granted while we were already running, so a restart is pending.
    var needsRestart: Bool {
        isGranted && grantedAtLaunch == false
    }

    /// Re-read the permission. Cheap enough for opening a menu, never called on
    /// the hotkey path.
    @discardableResult
    func refreshPermission() -> Bool {
        isGranted = CGPreflightScreenCaptureAccess()
        if grantedAtLaunch == nil { grantedAtLaunch = isGranted }
        return isGranted
    }

    /// Show the system prompt, if and only if previews are switched on and we do
    /// not have access yet.
    ///
    /// `CGRequestScreenCaptureAccess()` blocks while the dialog is up, so it must
    /// not run on the main thread. macOS shows that dialog only once per app
    /// identity; afterwards the call just returns false and the user has to go
    /// through System Settings, which is why the menu offers that route too.
    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        refreshPermission()
        guard SettingsStore.shared.value.thumbnails, !isGranted else {
            completion(isGranted)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                self.isGranted = granted
                completion(granted)
            }
        }
    }

    /// Deep-link into the Screen Recording list.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Refresh the catalogue of capturable windows. Returns immediately; `then`
    /// runs on the main thread once the catalogue is usable — right away if it is
    /// already fresh, so a warm session never waits for anything.
    func prepare(then: (() -> Void)? = nil) {
        guard isAvailable else { return }
        let now = CACurrentMediaTime()
        if !windowsByID.isEmpty, now - contentFetchedAt <= catalogueTTL {
            then?()
            return
        }
        if let then { pendingAfterFetch.append(then) }
        guard !contentFetchInFlight else { return }
        contentFetchInFlight = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content?.windows ?? []
            await MainActor.run {
                self.windowsByID = Dictionary(windows.map { (CGWindowID($0.windowID), $0) },
                                              uniquingKeysWith: { first, _ in first })
                self.contentFetchedAt = CACurrentMediaTime()
                self.contentFetchInFlight = false
                let callbacks = self.pendingAfterFetch
                self.pendingAfterFetch = []
                callbacks.forEach { $0() }
            }
        }
    }

    /// Whatever we already have, right now. Never blocks, never captures.
    func cached(for entry: WindowEntry) -> NSImage? {
        guard let id = entry.cgWindowID else { return nil }
        return cache[id]?.image
    }

    /// Kick off a capture if the cached preview is missing or stale.
    func request(for entry: WindowEntry, size: CGSize) {
        guard isAvailable, !entry.isMinimized, let id = entry.cgWindowID else { return }
        let now = CACurrentMediaTime()
        if let hit = cache[id], now - hit.at < ttl { return }
        guard !inFlight.contains(id), let window = windowsByID[id] else { return }
        inFlight.insert(id)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(size.width * scale)
            configuration.height = Int(size.height * scale)
            configuration.showsCursor = false
            configuration.scalesToFit = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cgImage = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)

            await MainActor.run {
                self.inFlight.remove(id)
                guard let cgImage else { return }
                let image = NSImage(cgImage: cgImage,
                                    size: NSSize(width: CGFloat(cgImage.width) / scale,
                                                 height: CGFloat(cgImage.height) / scale))
                self.cache[id] = (image, CACurrentMediaTime())
                entry.thumbnail = image
                NotificationCenter.default.post(name: ThumbnailProvider.didUpdate, object: entry)
            }
        }
    }

    func purge(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }
}
