import AppKit
import ServiceManagement

/// Menu bar entry — Tappi has no windows of its own, so this is the whole UI.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settings: Settings { SettingsStore.shared.value }

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                     accessibilityDescription: "Tappi")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let modifier = settings.holdModifier.symbol

        let status = SwitcherController.shared.isRunning && AX.isTrusted
            ? "Aktiv · \(modifier)Tab · \(WindowStore.shared.entries.count) Fenster"
            : "Inaktiv · Bedienungshilfen fehlen"
        menu.addItem(disabled(status))

        if !AX.isTrusted {
            menu.addItem(action("Bedienungshilfen freigeben …", #selector(openAccessibility)))
        }
        menu.addItem(.separator())

        let modifierMenu = NSMenu()
        for candidate in [HoldModifier.option, .command, .control] {
            let entry = action("\(candidate.symbol) \(label(for: candidate))", #selector(setModifier(_:)))
            entry.representedObject = candidate.rawValue
            entry.state = settings.holdModifier == candidate ? .on : .off
            modifierMenu.addItem(entry)
        }
        let modifierItem = NSMenuItem(title: "Modifier", action: nil, keyEquivalent: "")
        modifierItem.submenu = modifierMenu
        menu.addItem(modifierItem)

        let delayMenu = NSMenu()
        for value in [0, 60, 120, 200] {
            let title = value == 0 ? "Sofort (wie Windows)" : "\(value) ms"
            let entry = action(title, #selector(setDelay(_:)))
            entry.representedObject = value
            entry.state = settings.showDelayMs == value ? .on : .off
            delayMenu.addItem(entry)
        }
        let delayItem = NSMenuItem(title: "Einblendeverzögerung", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let sizeMenu = NSMenu()
        for value in [112.0, 148.0, 190.0, 240.0] {
            let entry = action("\(Int(value)) pt", #selector(setTileSize(_:)))
            entry.representedObject = value
            entry.state = settings.tileSize == value ? .on : .off
            sizeMenu.addItem(entry)
        }
        let sizeItem = NSMenuItem(title: "Kachelgröße", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        menu.addItem(toggle("Vorschaubilder", #selector(toggleThumbnails), settings.thumbnails))
        menu.addItem(toggle("Minimierte Fenster", #selector(toggleMinimized), settings.includeMinimized))
        menu.addItem(toggle("Fenster anderer Spaces", #selector(toggleSpaces), settings.includeOtherSpaces))
        menu.addItem(toggle("Fenster ausgeblendeter Apps", #selector(toggleHidden), settings.includeHiddenApps))
        menu.addItem(toggle("Auswahl folgt der Maus", #selector(toggleHover), settings.mouseHover))

        menu.addItem(.separator())
        menu.addItem(toggle("Bei der Anmeldung starten", #selector(toggleLaunchAtLogin), settings.launchAtLogin))
        menu.addItem(action("Einstellungsdatei öffnen", #selector(openSettingsFile)))
        menu.addItem(.separator())
        menu.addItem(action("Tappi beenden", #selector(quit)))
    }

    private func label(for modifier: HoldModifier) -> String {
        switch modifier {
        case .option: return "Wahltaste (Alt)"
        case .command: return "Befehlstaste"
        case .control: return "Control"
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    private func toggle(_ title: String, _ selector: Selector, _ on: Bool) -> NSMenuItem {
        let entry = action(title, selector)
        entry.state = on ? .on : .off
        return entry
    }

    // MARK: - Actions

    @objc private func setModifier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let modifier = HoldModifier(rawValue: raw) else { return }
        SettingsStore.shared.mutate { $0.holdModifier = modifier }
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        SettingsStore.shared.mutate { $0.showDelayMs = value }
    }

    @objc private func setTileSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        SettingsStore.shared.mutate { $0.tileSize = value }
    }

    @objc private func toggleThumbnails() {
        let enabling = !settings.thumbnails
        SettingsStore.shared.mutate { $0.thumbnails = enabling }
        // Only ask for Screen Recording when the user actually opts in.
        ThumbnailProvider.shared.refreshPermission()
        if enabling && !CGPreflightScreenCaptureAccess() {
            ThumbnailProvider.shared.requestPermission()
        }
        ThumbnailProvider.shared.prepare()
    }

    @objc private func toggleMinimized() { SettingsStore.shared.mutate { $0.includeMinimized.toggle() } }
    @objc private func toggleSpaces() { SettingsStore.shared.mutate { $0.includeOtherSpaces.toggle() } }
    @objc private func toggleHidden() { SettingsStore.shared.mutate { $0.includeHiddenApps.toggle() } }
    @objc private func toggleHover() { SettingsStore.shared.mutate { $0.mouseHover.toggle() } }

    @objc private func toggleLaunchAtLogin() {
        let enabling = !settings.launchAtLogin
        do {
            if enabling {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            SettingsStore.shared.mutate { $0.launchAtLogin = enabling }
        } catch {
            NSLog("Tappi: launch at login failed: \(error)")
        }
    }

    @objc private func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: Settings.url.path) {
            SettingsStore.shared.value.save()
        }
        NSWorkspace.shared.open(Settings.url)
    }

    @objc private func openAccessibility() {
        AX.requestTrust()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
