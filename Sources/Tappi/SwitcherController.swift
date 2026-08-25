import AppKit
import CoreGraphics

/// Drives one switching session, mirroring the Windows task switcher state machine.
///
/// The rules being reproduced:
///   • Index 0 is the current window, index 1 the previous one — so a quick
///     press-and-release toggles between the last two windows.
///   • Shift on the first press jumps to the end of the list.
///   • MRU is only re-ordered on commit, never while cycling. That is what makes
///     repeated toggling between two windows work.
///   • Esc aborts without switching; Ctrl+Alt+Tab opens the list "sticky".
final class SwitcherController: NSObject, EventTapDelegate {
    static let shared = SwitcherController()

    private enum State { case idle, holding, sticky }

    private let tap = EventTap()
    private let panel = SwitcherPanel()
    private var state: State = .idle
    private var list: [WindowEntry] = []
    private var selection = 0
    private var showTimer: Timer?
    private var outsideClickMonitor: Any?
    private var watchdog: Timer?
    private var lastActivity: CFTimeInterval = 0
    private var modifierMisses = 0
    private var keyDownAt: CFTimeInterval = 0

    private var settings: Settings { SettingsStore.shared.value }

    private override init() {
        super.init()
        tap.delegate = self
        panel.onSelect = { [weak self] index in
            self?.selection = index
            self?.panel.select(index)
        }
        panel.onActivate = { [weak self] index in
            self?.selection = index
            self?.commit()
        }
        panel.onClose = { [weak self] index in
            self?.closeWindow(at: index)
        }
    }

    @discardableResult
    func start() -> Bool {
        panel.warmUp()
        return tap.install()
    }

    func stop() { tap.uninstall() }

    var isRunning: Bool { tap.isEnabled }

    // MARK: - Key handling

    func eventTap(keyDown keyCode: Int64, flags: CGEventFlags) -> Bool {
        let modifier = settings.holdModifier
        guard state != .idle else {
            guard flags.contains(modifier.flag),
                  keyCode == KeyCode.tab || keyCode == KeyCode.grave
            else { return false }
            let sticky = modifier != .control && flags.contains(.maskControl)
            begin(scope: keyCode == KeyCode.grave ? .currentApp : .allWindows,
                  backwards: flags.contains(.maskShift),
                  sticky: sticky)
            return true
        }

        switch keyCode {
        case KeyCode.tab, KeyCode.grave:
            step(flags.contains(.maskShift) ? -1 : 1)
        case KeyCode.right, KeyCode.down:
            step(1)
        case KeyCode.left, KeyCode.up:
            step(-1)
        case KeyCode.escape:
            cancel()
        case KeyCode.ret, KeyCode.space:
            commit()
        case KeyCode.w:
            closeWindow(at: selection)
        case KeyCode.q:
            quitApp(at: selection)
        default:
            break // Swallow everything else for the duration of the session.
        }
        return true
    }

    func eventTap(flagsChanged keyCode: Int64, flags: CGEventFlags) -> Bool {
        // Sticky sessions deliberately outlive the modifier.
        guard state == .holding else { return false }
        if !flags.contains(settings.holdModifier.flag) {
            commit()
        }
        // Never swallow modifier events — apps track modifier state themselves.
        return false
    }

    // MARK: - Session

    private func begin(scope: SwitchScope, backwards: Bool, sticky: Bool) {
        keyDownAt = CACurrentMediaTime()
        list = WindowStore.shared.sessionList(scope: scope)
        if EventTap.debug {
            NSLog("Tappi/session: begin scope=%@ candidates=%d store=%d sticky=%@",
                  String(describing: scope), list.count,
                  WindowStore.shared.entries.count, sticky ? "yes" : "no")
        }
        guard list.count > 1 else {
            // Nothing to switch to, exactly like Windows with a single window.
            list = []
            return
        }
        selection = backwards ? list.count - 1 : 1
        state = sticky ? .sticky : .holding

        startWatchdog()

        let delay = Double(settings.showDelayMs) / 1000.0
        if delay <= 0 || sticky {
            present()
        } else {
            showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.present()
            }
        }
    }

    private func present() {
        showTimer?.invalidate()
        showTimer = nil
        guard state != .idle, !panel.isPresented else { return }
        panel.present(entries: list, selected: selection)
        if EventTap.debug {
            let ms = (CACurrentMediaTime() - keyDownAt) * 1000
            NSLog("Tappi/session: visible after %.1f ms (%d windows, selection=%d)",
                  ms, list.count, selection)
        }
        installOutsideClickMonitor()
    }

    private func step(_ delta: Int) {
        guard !list.isEmpty else { return }
        lastActivity = CACurrentMediaTime()
        selection = (selection + delta + list.count) % list.count
        // Cycling means the user wants to see the list, so skip any remaining delay.
        if !panel.isPresented { present() } else { panel.select(selection) }
    }

    private func commit() {
        guard state != .idle else { return }
        let target = list.indices.contains(selection) ? list[selection] : nil
        end()
        guard let target else { return }
        // Re-rank immediately so a follow-up toggle sees the right order, without
        // waiting for the focus notification to make its way back to us.
        WindowStore.shared.promote(target)
        target.focus()
    }

    private func cancel() {
        end()
    }

    private func end() {
        showTimer?.invalidate()
        showTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        removeOutsideClickMonitor()
        panel.dismiss()
        state = .idle
        list = []
        selection = 0
    }

    // MARK: - Watchdog

    /// A session swallows every keystroke, so losing the modifier-release event —
    /// a dropped tap, a Space switch, a security dialog stealing input — must never
    /// be able to strand the keyboard. This is the escape hatch.
    /// Consecutive 200 ms ticks without the modifier before we force the session shut.
    private static let modifierMissLimit = ProcessInfo.processInfo
        .environment["TAPPI_WATCHDOG_TICKS"].flatMap(Int.init) ?? 5

    private func startWatchdog() {
        watchdog?.invalidate()
        lastActivity = CACurrentMediaTime()
        modifierMisses = 0
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkWatchdog()
        }
    }

    private func checkWatchdog() {
        switch state {
        case .idle:
            watchdog?.invalidate()
            watchdog = nil
        case .holding:
            // The flagsChanged event is the real signal; this is only here for the
            // case where we never receive it. Requiring several consecutive misses
            // keeps a momentarily stale session state from cutting a live session
            // short, at the cost of a delay nobody sees unless something broke.
            if CGEventSource.flagsState(.combinedSessionState).contains(settings.holdModifier.flag) {
                modifierMisses = 0
            } else {
                modifierMisses += 1
                if modifierMisses >= Self.modifierMissLimit {
                    if EventTap.debug { NSLog("Tappi/session: watchdog released a stuck session") }
                    commit()
                }
            }
        case .sticky:
            if CACurrentMediaTime() - lastActivity > 20 { cancel() }
        }
    }

    // MARK: - Window actions

    private func closeWindow(at index: Int) {
        guard list.indices.contains(index) else { return }
        let entry = list[index]
        AX.close(entry.axWindow)
        list.remove(at: index)
        guard list.count > 1 else { end(); return }
        selection = min(selection, list.count - 1)
        panel.present(entries: list, selected: selection)
        WindowStore.shared.refresh()
    }

    private func quitApp(at index: Int) {
        guard list.indices.contains(index) else { return }
        let pid = list[index].pid
        NSRunningApplication(processIdentifier: pid)?.terminate()
        list.removeAll { $0.pid == pid }
        guard list.count > 1 else { end(); return }
        selection = min(selection, list.count - 1)
        panel.present(entries: list, selected: selection)
        WindowStore.shared.refresh()
    }

    // MARK: - Mouse

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.cancel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
