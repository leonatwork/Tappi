import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// The other tools of the "I love macOS, but I miss some Windows features" package.
struct SiblingApp {
    let name: String
    /// Key of the one-line description in Localizable.strings.
    let descriptionKey: String
    let url: URL

    static let all = [
        SiblingApp(name: "Klemmi", descriptionKey: "moreApps.klemmi",
                   url: URL(string: "https://github.com/leonatwork/Klemmi")!),
        SiblingApp(name: "Snapline", descriptionKey: "moreApps.snapline",
                   url: URL(string: "https://github.com/leonatwork/snapline")!),
        SiblingApp(name: "Snapboard", descriptionKey: "moreApps.snapboard",
                   url: URL(string: "https://github.com/leonatwork/snapboard")!),
    ]

    static let packageURL = URL(string:
        "https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories")!
}

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
        // Hand edits to settings.json take effect without a restart.
        SettingsStore.shared.reloadIfChangedOnDisk()
        menu.removeAllItems()
        let modifier = settings.holdModifier.symbol

        let running = SwitcherController.shared.isRunning && AX.isTrusted
        let status: String
        if !running {
            status = tr("status.inactive")
        } else if !WindowStore.shared.isOperational {
            status = tr("status.noWindows")
        } else {
            let previews = ThumbnailProvider.shared
            let suffix = (settings.thumbnails && !previews.isGranted) ? tr("status.withoutPreviews") : ""
            let count = WindowStore.shared.entries.count
            status = tr(count == 1 ? "status.active.one" : "status.active.other", modifier, count, suffix)
        }
        menu.addItem(disabled(status))

        if !running || !WindowStore.shared.isOperational {
            menu.addItem(action(tr("menu.grantAccessibility"), #selector(openAccessibility)))
        }
        menu.addItem(.separator())

        let languageMenu = NSMenu()
        for language in InterfaceLanguage.allCases {
            let entry = action(language.nativeName ?? tr("language.system"), #selector(setLanguage(_:)))
            entry.representedObject = language.rawValue
            entry.state = (settings.language ?? .system) == language ? .on : .off
            languageMenu.addItem(entry)
            if language == .system { languageMenu.addItem(.separator()) }
        }
        menu.addItem(submenu(tr("menu.language"), languageMenu))

        let modifierMenu = NSMenu()
        for candidate in [HoldModifier.option, .command, .control] {
            let entry = action("\(candidate.symbol) \(label(for: candidate))", #selector(setModifier(_:)))
            entry.representedObject = candidate.rawValue
            entry.state = settings.holdModifier == candidate ? .on : .off
            modifierMenu.addItem(entry)
        }
        menu.addItem(submenu(tr("menu.modifier"), modifierMenu))

        let delayMenu = NSMenu()
        for value in [0, 60, 120, 200] {
            let title = value == 0 ? tr("delay.instant") : "\(value) ms"
            let entry = action(title, #selector(setDelay(_:)))
            entry.representedObject = value
            entry.state = settings.showDelayMs == value ? .on : .off
            delayMenu.addItem(entry)
        }
        menu.addItem(submenu(tr("menu.showDelay"), delayMenu))

        let sizeMenu = NSMenu()
        for value in [112.0, 148.0, 190.0, 240.0, 320.0] {
            let entry = action("\(Int(value)) pt", #selector(setTileSize(_:)))
            entry.representedObject = value
            entry.state = settings.tileSize == value ? .on : .off
            sizeMenu.addItem(entry)
        }
        menu.addItem(submenu(tr("menu.tileSize"), sizeMenu))

        let columnsMenu = NSMenu()
        for value in [4, 5, 6, 7, 8, 10] {
            let entry = action("\(value)", #selector(setMaxColumns(_:)))
            entry.representedObject = value
            entry.state = settings.maxColumns == value ? .on : .off
            columnsMenu.addItem(entry)
        }
        menu.addItem(submenu(tr("menu.tilesPerRow"), columnsMenu))

        menu.addItem(.separator())
        let replace = toggle(tr("menu.replaceSystemSwitcher"), #selector(toggleReplaceSystemSwitcher),
                             settings.replaceSystemSwitcher)
        if settings.holdModifier != .command {
            replace.isEnabled = false
            replace.toolTip = tr("tooltip.replaceSystemSwitcher")
        }
        menu.addItem(replace)
        if !SystemSwitcher.systemShortcutsEnabled && !SystemSwitcher.isSuppressed {
            menu.addItem(action(tr("menu.restoreSystemSwitcher"), #selector(restoreSystemSwitcher)))
        }
        let previews = ThumbnailProvider.shared
        menu.addItem(toggle(tr("menu.windowPreviews"), #selector(toggleThumbnails), settings.thumbnails))
        if settings.thumbnails && !previews.isGranted {
            let grant = action(tr("menu.grantScreenRecording"), #selector(grantScreenRecording))
            grant.toolTip = tr("tooltip.grantScreenRecording")
            menu.addItem(indented(grant))
        } else if previews.needsRestart {
            menu.addItem(indented(action(tr("menu.restartForPreviews"), #selector(restartTappi))))
        }
        menu.addItem(toggle(tr("menu.minimizedWindows"), #selector(toggleMinimized), settings.includeMinimized))
        menu.addItem(toggle(tr("menu.otherSpaces"), #selector(toggleSpaces), settings.includeOtherSpaces))
        menu.addItem(toggle(tr("menu.hiddenApps"), #selector(toggleHidden), settings.includeHiddenApps))
        menu.addItem(toggle(tr("menu.mouseHover"), #selector(toggleHover), settings.mouseHover))

        menu.addItem(.separator())
        menu.addItem(toggle(tr("menu.launchAtLogin"), #selector(toggleLaunchAtLogin), settings.launchAtLogin))
        menu.addItem(action(tr("menu.openSettingsFile"), #selector(openSettingsFile)))
        menu.addItem(action(tr("menu.openDiagnostics"), #selector(openDiagnostics)))
        menu.addItem(action(tr("menu.restart"), #selector(restartTappi)))
        menu.addItem(.separator())
        menu.addItem(submenu(tr("menu.moreApps"), moreAppsMenu()))
        menu.addItem(.separator())
        menu.addItem(action(tr("menu.quit"), #selector(quit)))
    }

    /// The sibling tools from the same package, each opening its GitHub page.
    private func moreAppsMenu() -> NSMenu {
        let menu = NSMenu()
        for app in SiblingApp.all {
            let entry = action("\(app.name) – \(tr(app.descriptionKey))", #selector(openLink(_:)))
            entry.representedObject = app.url
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let package = action(tr("moreApps.package"), #selector(openLink(_:)))
        package.representedObject = SiblingApp.packageURL
        menu.addItem(package)
        return menu
    }

    private func label(for modifier: HoldModifier) -> String {
        switch modifier {
        case .option: return tr("modifier.option")
        case .command: return tr("modifier.command")
        case .control: return tr("modifier.control")
        }
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = submenu
        return entry
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

    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
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

    @objc private func setMaxColumns(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        SettingsStore.shared.mutate { $0.maxColumns = value }
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
        Self.openInTextEditor(Settings.url)
    }

    /// The default app for .json is often Xcode or a browser, neither of which suits a
    /// quick edit. The file goes to the default plain-text editor instead, or TextEdit
    /// if that default is Xcode. If nothing opens, Finder shows the file.
    static func openInTextEditor(_ url: URL) {
        let workspace = NSWorkspace.shared
        let skipped: Set<String> = ["com.apple.dt.Xcode"]
        let candidates = [
            workspace.urlForApplication(toOpen: .plainText),
            workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit"),
        ]
        let editor = candidates.compactMap { $0 }.first { app in
            guard let id = Bundle(url: app)?.bundleIdentifier else { return false }
            return !skipped.contains(id)
        }
        guard let editor else {
            workspace.activateFileViewerSelecting([url])
            return
        }
        workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async { workspace.activateFileViewerSelecting([url]) }
        }
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
