import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var trustPoller: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock tile, no main menu, never steals focus.
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController()

        if AX.isTrusted {
            begin()
        } else {
            NSLog("Tappi: waiting for Accessibility permission")
            AX.requestTrust()
            waitForTrust()
        }
    }

    /// Accessibility can be granted while we are already running, and the system
    /// gives us no notification for it, so poll cheaply until it lands.
    private func waitForTrust() {
        trustPoller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AX.isTrusted else { return }
            timer.invalidate()
            self?.trustPoller = nil
            self?.begin()
        }
        trustPoller?.tolerance = 0.5
    }

    private func begin() {
        WindowStore.shared.start()
        ThumbnailProvider.shared.refreshPermission()
        ThumbnailProvider.shared.prepare()
        let installed = SwitcherController.shared.start()
        NSLog("Tappi: accessibility=granted eventTap=%@ screenRecording=%@",
              installed ? "installed" : "FAILED",
              CGPreflightScreenCaptureAccess() ? "granted" : "denied")
        if !installed {
            NSLog("Tappi: the event tap could not be installed — remove and re-add Tappi in "
                  + "System Settings ▸ Privacy & Security ▸ Accessibility, then relaunch.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSLog("Tappi: tracking %d windows", WindowStore.shared.entries.count)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwitcherController.shared.stop()
    }
}
