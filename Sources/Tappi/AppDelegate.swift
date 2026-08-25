import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var readinessTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var storeStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock tile, no main menu, never steals focus.
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController()
        installTerminationHandlers()

        Diagnostics.reset()
        Diagnostics.log("launched from \(Bundle.main.bundlePath)")
        SystemSwitcher.repairOrphanedState()
        ThumbnailProvider.shared.refreshPermission()

        if !AX.isTrusted {
            Diagnostics.log("Accessibility not granted yet — prompting")
            AX.requestTrust()
        }
        waitUntilReady()
    }

    /// Keep trying until Tappi is genuinely working.
    ///
    /// Both halves of "ready" can arrive late or fail transiently: the user may
    /// grant Accessibility while we run, and creating the event tap can fail even
    /// though `AXIsProcessTrusted()` says yes. A single attempt at launch would
    /// leave Tappi permanently dead in either case, so this retries and reports
    /// what it sees.
    private func waitUntilReady() {
        attemptStart()
        guard readinessTimer == nil else { return }
        readinessTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.attemptStart()
        }
        readinessTimer?.tolerance = 0.5
    }

    private var lastReport = ""

    private func attemptStart() {
        guard !SwitcherController.shared.isRunning else {
            // Already up. Report once when the window list first fills in.
            if storeStarted, WindowStore.shared.isOperational, lastReport != "operational" {
                lastReport = "operational"
                Diagnostics.log("ready — tracking \(WindowStore.shared.entries.count) windows")
                readinessTimer?.invalidate()
                readinessTimer = nil
            }
            return
        }

        guard AX.isTrusted else {
            report("waiting for Accessibility permission")
            return
        }

        if !storeStarted {
            WindowStore.shared.start()
            storeStarted = true
        }

        if SwitcherController.shared.start() {
            Diagnostics.log("event tap installed; screen recording="
                            + (ThumbnailProvider.shared.isAvailable ? "granted" : "off"))
            lastReport = ""
        } else {
            // The one failure macOS gives no useful error for: the process is
            // "trusted" but not actually ticked in the Accessibility list.
            report("Accessibility reports as granted, but the event tap was refused — "
                   + "remove Tappi from System Settings ▸ Privacy & Security ▸ Accessibility "
                   + "and add it again (a rebuild invalidates the old entry)")
        }
    }

    /// Log a recurring condition only when it changes, so the file stays readable.
    private func report(_ message: String) {
        guard lastReport != message else { return }
        lastReport = message
        Diagnostics.log(message)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Disabling the system switcher outlives our process, so handing it back
        // is not optional.
        SystemSwitcher.restore(force: true)
        SwitcherController.shared.stop()
    }

    /// `pkill` and friends bypass `applicationWillTerminate`, which would leave the
    /// machine with no switcher at all. Catch the signals and clean up first.
    private func installTerminationHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                SystemSwitcher.restore(force: true)
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
