import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var readinessTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var storeStarted = false
    private var ownsLifecycle = false
    private var restartTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock tile, no main menu, never steals focus.
        NSApp.setActivationPolicy(.accessory)

        let arguments = ProcessInfo.processInfo.arguments
        let restart = RestartRequest(arguments: arguments)
        // A malformed restart must not silently turn into an ordinary launch.
        guard restart != nil || !arguments.contains(RestartRequest.argument) else {
            NSApp.terminate(nil)
            return
        }
        checkStartup(restart: restart)
    }

    private func checkStartup(restart: RestartRequest?) {
        let remaining = restart.map { $0.waitDeadline - ProcessInfo.processInfo.systemUptime }
        switch InstanceLifecycle.startup(hasPeer: anotherInstanceIsRunning(), restartRemaining: remaining) {
        case .exit:
            // If acceptance won the race with this timeout, use the exit-wait
            // interval instead of abandoning a replacement the parent relies on.
            if let restart, restart.decide(.cancelled) == .accepted,
               ProcessInfo.processInfo.systemUptime < restart.waitDeadline {
                checkStartup(restart: restart)
                return
            }
            restart?.remove()
            restartTimer?.invalidate()
            restartTimer = nil
            NSLog("Tappi: another instance is still running — exiting without taking ownership")
            NSApp.terminate(nil)
        case .wait:
            guard let restart else { return }
            guard restart.decision != .cancelled, restart.announceReady() else {
                restart.remove()
                restartTimer?.invalidate()
                restartTimer = nil
                NSApp.terminate(nil)
                return
            }
            guard restartTimer == nil else { return }
            restartTimer = Timer.scheduledTimer(withTimeInterval: RestartRequest.pollInterval,
                                                repeats: true) { [weak self] _ in
                self?.checkStartup(restart: restart)
            }
        case .start:
            restart?.remove()
            restartTimer?.invalidate()
            restartTimer = nil
            beginStartup()
        }
    }

    private func beginStartup() {
        ownsLifecycle = true
        SystemSwitcher.claimOwnership()

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
            Diagnostics.log("event tap installed")
            lastReport = ""
            askForScreenRecording()
        } else {
            // The one failure macOS gives no useful error for: the process is
            // "trusted" but not actually ticked in the Accessibility list.
            // Localized, unlike the purely technical lines: this one tells the
            // user what to do in System Settings.
            report(tr("diagnostics.eventTapRefused"))
        }
    }

    /// Previews are on by default, so the permission has to be requested rather
    /// than waited for — nobody discovers it by toggling a menu item they cannot
    /// see the effect of.
    private func askForScreenRecording() {
        ThumbnailProvider.shared.requestAccessIfNeeded { granted in
            if granted {
                Diagnostics.log(ThumbnailProvider.shared.needsRestart
                    ? "screen recording granted — restart Tappi to enable previews"
                    : "screen recording granted")
            } else if SettingsStore.shared.value.thumbnails {
                // Names the menu item, so it has to match the menu's language.
                Diagnostics.log(tr("diagnostics.screenRecordingDenied", tr("menu.grantScreenRecording")))
            }
        }
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != mine && !$0.isTerminated }
    }

    /// Log a recurring condition only when it changes, so the file stays readable.
    private func report(_ message: String) {
        guard lastReport != message else { return }
        lastReport = message
        Diagnostics.log(message)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
    }

    private func cleanUp() {
        restartTimer?.invalidate()
        restartTimer = nil
        // Rejected/waiting copies must not even initialize the shared controller:
        // its initializer creates the panel and reads settings.
        guard ownsLifecycle else { return }
        ownsLifecycle = false
        readinessTimer?.invalidate()
        readinessTimer = nil
        SwitcherController.shared.stop()
        SystemSwitcher.relinquishOwnership()
    }

    /// `pkill` and friends bypass `applicationWillTerminate`, which would leave the
    /// machine with no switcher at all. Catch the signals and clean up first.
    private func installTerminationHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.cleanUp()
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
