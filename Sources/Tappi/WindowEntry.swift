import AppKit
import ApplicationServices

/// One switchable window. Identity is the `AXUIElement`, which stays stable for
/// the lifetime of the window, so MRU position survives title and size changes.
final class WindowEntry {
    let axWindow: AXUIElement
    let pid: pid_t

    var title: String
    var appName: String
    var icon: NSImage?
    var isMinimized: Bool
    var isHidden: Bool
    var isOnActiveSpace: Bool
    /// Resolved by matching AX frames against the CoreGraphics window list.
    /// Only needed for thumbnails; `nil` simply means "icon only".
    var cgWindowID: CGWindowID?
    var frame: CGRect?

    /// Cached thumbnail plus the time it was captured, so we can refresh lazily.
    var thumbnail: NSImage?
    var thumbnailCapturedAt: CFTimeInterval = 0

    init(axWindow: AXUIElement, pid: pid_t, title: String, appName: String,
         icon: NSImage?, isMinimized: Bool, isHidden: Bool, isOnActiveSpace: Bool,
         frame: CGRect?, cgWindowID: CGWindowID?) {
        self.axWindow = axWindow
        self.pid = pid
        self.title = title
        self.appName = appName
        self.icon = icon
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isOnActiveSpace = isOnActiveSpace
        self.frame = frame
        self.cgWindowID = cgWindowID
    }

    /// What the tile shows under the icon.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    func matches(_ element: AXUIElement) -> Bool {
        CFEqual(axWindow, element)
    }

    /// Bring this window to the front the way Windows does: restore it if
    /// minimized, raise it within its app, then activate the app itself.
    func focus() {
        // Activation goes first: it is cheap, never blocks, and gives the user
        // instant feedback. The AX calls may stall on a wedged app, so they run
        // off the main thread where a stall costs nothing.
        let app = NSRunningApplication(processIdentifier: pid)
        if app?.isHidden == true { app?.unhide() }
        app?.activate(options: [])

        let window = axWindow
        let pid = pid
        let wasMinimized = isMinimized
        DispatchQueue.global(qos: .userInitiated).async {
            if wasMinimized { AX.setMinimized(window, false) }
            AX.raise(window)
            AXUIElementSetAttributeValue(AX.application(pid), kAXFrontmostAttribute as CFString,
                                         true as CFTypeRef)
        }
    }
}
