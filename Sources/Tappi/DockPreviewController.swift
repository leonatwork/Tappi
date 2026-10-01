import AppKit
import ApplicationServices

/// Adds window previews to application Dock items without modifying or injecting into Dock.
/// macOS exposes Dock items through Accessibility, so this remains best-effort and
/// automatically becomes inactive when Accessibility is unavailable.
final class DockPreviewController {
    static let shared = DockPreviewController()

    private let panel = SwitcherPanel()
    private var timer: Timer?
    private var hoveredPID: pid_t?
    private var leaveDeadline: CFTimeInterval?

    private struct DockItem {
        let pid: pid_t
        let frame: CGRect
    }

    private init() {
        panel.onActivate = { [weak self] index in self?.activate(index) }
        panel.onClose = { [weak self] index in self?.close(index) }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.04
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dismiss()
    }

    private func tick() {
        guard AX.isTrusted, SettingsStore.shared.value.dockPreviews != false else {
            dismiss()
            return
        }

        let mouse = NSEvent.mouseLocation
        if panel.containsScreenPoint(mouse) {
            leaveDeadline = nil
            return
        }

        if let quartzMouse = CGEvent(source: nil)?.location,
           let item = dockApplicationItem(at: quartzMouse, cocoaMouse: mouse) {
            leaveDeadline = nil
            guard item.pid != hoveredPID || !panel.isPresented else { return }
            let entries = WindowStore.shared.windows(for: item.pid)
            guard !entries.isEmpty, let screen = NSScreen.screens.first(where: { $0.frame.intersects(item.frame) }) else {
                dismiss()
                return
            }
            hoveredPID = item.pid
            panel.presentDock(entries: entries, on: screen, anchoredTo: item.frame)
            return
        }

        guard panel.isPresented else { return }
        let now = CACurrentMediaTime()
        if leaveDeadline == nil { leaveDeadline = now + 0.30 }
        if now >= leaveDeadline! { dismiss() }
    }

    private func dockApplicationItem(at quartzPoint: CGPoint, cocoaMouse: CGPoint) -> DockItem? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(quartzPoint.x), Float(quartzPoint.y), &element) == .success,
              var current = element else { return nil }

        for _ in 0..<5 {
            let subrole = AX.string(current, kAXSubroleAttribute) ?? ""
            if subrole == "AXApplicationDockItem" {
                var pid: pid_t?
                if let url = AX.attribute(current, kAXURLAttribute, as: URL.self) {
                    pid = NSWorkspace.shared.runningApplications.first(where: {
                        $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
                    })?.processIdentifier
                }
                if pid == nil {
                    let title = AX.string(current, kAXTitleAttribute) ?? ""
                    pid = NSWorkspace.shared.runningApplications.first(where: {
                        $0.activationPolicy == .regular && $0.localizedName == title
                    })?.processIdentifier
                }
                guard let pid, let quartzFrame = AX.frame(current) else { return nil }
                let cocoaFrame = CGRect(
                    x: cocoaMouse.x + quartzFrame.minX - quartzPoint.x,
                    y: cocoaMouse.y + quartzPoint.y - quartzFrame.maxY,
                    width: quartzFrame.width,
                    height: quartzFrame.height)
                return DockItem(pid: pid, frame: cocoaFrame)
            }
            guard let parent = AX.element(current, kAXParentAttribute) else { break }
            current = parent
        }
        return nil
    }

    private func activate(_ index: Int) {
        guard panel.entries.indices.contains(index) else { return }
        let entry = panel.entries[index]
        dismiss()
        WindowStore.shared.promote(entry)
        entry.focus()
    }

    private func close(_ index: Int) {
        guard panel.entries.indices.contains(index) else { return }
        AX.close(panel.entries[index].axWindow)
        WindowStore.shared.refresh()
        dismiss()
    }

    private func dismiss() {
        panel.dismiss()
        hoveredPID = nil
        leaveDeadline = nil
    }
}
