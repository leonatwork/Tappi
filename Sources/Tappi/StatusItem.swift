import AppKit
import ServiceManagement

/// Menu bar entry — Tappi has no windows of its own, so this is the whole UI.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settings: Settings { SettingsStore.shared.value }

    override init() {
        super.init()
        item.button?.image = StatusItemController.icon()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// A 2×2 window grid with one tile selected — the switcher's own picture.
    ///
    /// Drawn rather than taken from SF Symbols: every stock window glyph
    /// (`rectangle.on.rectangle` and friends) is two overlapping rectangles, which
    /// is precisely the AirPlay / screen-mirroring motif and unreadable next to it
    /// in the menu bar.
    private static func icon() -> NSImage {
        let tile = CGSize(width: 8, height: 6)
        let gap: CGFloat = 2
        let size = NSSize(width: tile.width * 2 + gap, height: tile.height * 2 + gap)
        let image = NSImage(size: size, flipped: false) { _ in
            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(x: CGFloat(column) * (tile.width + gap),
                                      y: CGFloat(row) * (tile.height + gap),
                                      width: tile.width, height: tile.height)
                    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                            xRadius: 1.5, yRadius: 1.5)
                    path.lineWidth = 1.2
                    // Top-left is the selected window.
                    if row == 1 && column == 0 {
                        NSColor.black.setFill()
                        path.fill()
                    } else {
                        NSColor.black.setStroke()
                        path.stroke()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening a menu is a fine moment to re-read a permission that may have
        // been granted in System Settings since we last looked.
        ThumbnailProvider.shared.refreshPermission()
        menu.removeAllItems()
        let modifier = settings.holdModifier.symbol

        let running = SwitcherController.shared.isRunning && AX.isTrusted
        let status: String
        if !running {
            status = text("Inactive · Accessibility permission missing", "Inaktiv · Bedienungshilfen fehlen")
        } else if !WindowStore.shared.isOperational {
            status = text("No windows detected · Check permissions", "Keine Fenster erkannt · Freigabe prüfen")
        } else {
            let previews = ThumbnailProvider.shared
            let suffix = (settings.thumbnails && !previews.isGranted) ? text(" · without previews", " · ohne Vorschauen") : ""
            status = text("Active · \(modifier)Tab · \(WindowStore.shared.entries.count) windows\(suffix)", "Aktiv · \(modifier)Tab · \(WindowStore.shared.entries.count) Fenster\(suffix)")
        }
        menu.addItem(disabled(status))

        if !running || !WindowStore.shared.isOperational {
            menu.addItem(action(text("Grant Accessibility…", "Bedienungshilfen freigeben …"), #selector(openAccessibility)))
        }
        menu.addItem(.separator())

        let languageMenu = NSMenu()
        for language in InterfaceLanguage.allCases {
            let title: String
            switch language {
            case .system: title = text("System default", "Systemstandard")
            case .english: title = "English"
            case .german: title = "Deutsch"
            }
            let entry = action(title, #selector(setLanguage(_:)))
            entry.representedObject = language.rawValue
            entry.state = (settings.language ?? .system) == language ? .on : .off
            languageMenu.addItem(entry)
        }
        let languageItem = NSMenuItem(title: text("Language", "Sprache"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

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
            let title = value == 0 ? text("Instant (like Windows)", "Sofort (wie Windows)") : "\(value) ms"
            let entry = action(title, #selector(setDelay(_:)))
            entry.representedObject = value
            entry.state = settings.showDelayMs == value ? .on : .off
            delayMenu.addItem(entry)
        }
        let delayItem = NSMenuItem(title: text("Show delay", "Einblendeverzögerung"), action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let sizeMenu = NSMenu()
        for value in [112.0, 148.0, 190.0, 240.0, 320.0] {
            let entry = action("\(Int(value)) pt", #selector(setTileSize(_:)))
            entry.representedObject = value
            entry.state = settings.tileSize == value ? .on : .off
            sizeMenu.addItem(entry)
        }
        let sizeItem = NSMenuItem(title: text("Tile size", "Kachelgröße"), action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        let replace = toggle(text("Replace system ⌘Tab", "System-⌘Tab ersetzen"), #selector(toggleReplaceSystemSwitcher),
                             settings.replaceSystemSwitcher)
        if settings.holdModifier != .command {
            replace.isEnabled = false
            replace.toolTip = text("Only applies when the modifier is ⌘.", "Nur relevant, wenn der Modifier ⌘ ist.")
        }
        menu.addItem(replace)
        if !SystemSwitcher.systemShortcutsEnabled && !SystemSwitcher.isSuppressed {
            menu.addItem(action(text("Restore system ⌘Tab", "System-⌘Tab wiederherstellen"), #selector(restoreSystemSwitcher)))
        }
        let previews = ThumbnailProvider.shared
        menu.addItem(toggle(text("Window previews", "Vorschaubilder"), #selector(toggleThumbnails), settings.thumbnails))
        if settings.thumbnails && !previews.isGranted {
            let grant = action(text("Grant Screen Recording…", "Bildschirmaufnahme freigeben …"), #selector(grantScreenRecording))
            grant.toolTip = text("Without this permission, Tappi shows app icons instead of window previews.", "Ohne diese Freigabe zeigt Tappi App-Symbole statt Fenstervorschauen.")
            menu.addItem(indented(grant))
        } else if previews.needsRestart {
            menu.addItem(indented(action(text("Restart to enable previews", "Neu starten, um Vorschauen zu aktivieren"),
                                         #selector(restartTappi))))
        }
        menu.addItem(toggle(text("Minimized windows", "Minimierte Fenster"), #selector(toggleMinimized), settings.includeMinimized))
        menu.addItem(toggle(text("Windows on other Spaces", "Fenster anderer Spaces"), #selector(toggleSpaces), settings.includeOtherSpaces))
        menu.addItem(toggle(text("Windows of hidden apps", "Fenster ausgeblendeter Apps"), #selector(toggleHidden), settings.includeHiddenApps))
        menu.addItem(toggle(text("Selection follows the mouse", "Auswahl folgt der Maus"), #selector(toggleHover), settings.mouseHover))

        menu.addItem(.separator())
        menu.addItem(toggle(text("Launch at login", "Bei der Anmeldung starten"), #selector(toggleLaunchAtLogin), settings.launchAtLogin))
        menu.addItem(action(text("Open settings file", "Einstellungsdatei öffnen"), #selector(openSettingsFile)))
        menu.addItem(action(text("Open diagnostics log", "Diagnoseprotokoll öffnen"), #selector(openDiagnostics)))
        menu.addItem(action(text("Restart Tappi", "Tappi neu starten"), #selector(restartTappi)))
        menu.addItem(.separator())
        menu.addItem(action(text("Quit Tappi", "Tappi beenden"), #selector(quit)))
    }

    private func text(_ english: String, _ german: String) -> String {
        (settings.language ?? .system).text(english, german)
    }

    private func label(for modifier: HoldModifier) -> String {
        switch modifier {
        case .option: return text("Option (Alt)", "Wahltaste (Alt)")
        case .command: return text("Command", "Befehlstaste")
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

    /// Visually subordinate an item to the one above it.
    private func indented(_ item: NSMenuItem) -> NSMenuItem {
        item.indentationLevel = 1
        return item
    }

    // MARK: - Actions

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = InterfaceLanguage(rawValue: raw) else { return }
        SettingsStore.shared.mutate { $0.language = language }
    }

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
        guard enabling else { return }
        // Switching previews on is the moment to ask for the permission they need.
        ThumbnailProvider.shared.requestAccessIfNeeded { granted in
            if granted {
                ThumbnailProvider.shared.prepare()
            } else {
                ThumbnailProvider.openSystemSettings()
            }
        }
    }

    @objc private func grantScreenRecording() {
        ThumbnailProvider.shared.requestAccessIfNeeded { granted in
            // The system dialog appears only once per app identity; every later
            // attempt has to go through System Settings.
            if granted {
                ThumbnailProvider.shared.prepare()
            } else {
                ThumbnailProvider.openSystemSettings()
            }
        }
    }

    /// Screen Recording only takes effect for a freshly started process.
    @objc private func restartTappi() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func toggleReplaceSystemSwitcher() {
        SettingsStore.shared.mutate { $0.replaceSystemSwitcher.toggle() }
    }

    @objc private func restoreSystemSwitcher() {
        SystemSwitcher.restore()
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

    @objc private func openDiagnostics() {
        NSWorkspace.shared.open(Diagnostics.url)
    }

    @objc private func openAccessibility() {
        AX.requestTrust()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
