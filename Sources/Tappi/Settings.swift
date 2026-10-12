import AppKit

/// Modifier that has to be held down for a switching session (the "Alt" in Alt-Tab).
enum HoldModifier: String, Codable {
    case option, command, control

    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        }
    }

    /// The raw keycodes that produce this modifier, so we can distinguish a real
    /// release from a `flagsChanged` event caused by some other modifier.
    var keyCodes: Set<Int64> {
        switch self {
        case .option: return [58, 61]
        case .command: return [55, 54]
        case .control: return [59, 62]
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        }
    }
}

/// What a single session lists.
enum SwitchScope: String, Codable {
    /// Every window of every app — this is what Windows does.
    case allWindows
    /// Only windows of the frontmost app (the "Alt+`" companion shortcut).
    case currentApp
}

struct Settings: Codable {
    /// Missing in older settings files; nil follows the system language.
    var language: InterfaceLanguage? = nil
    /// Modifier held down during a session. ⌘ is the default because it sits
    /// where Alt sits on a PC keyboard — directly left of the space bar — which is
    /// what Windows muscle memory reaches for.
    var holdModifier: HoldModifier = .command
    /// Disable the system's own ⌘Tab switcher while Tappi owns that shortcut.
    /// Without this macOS shows its switcher in front of ours.
    var replaceSystemSwitcher: Bool = true
    /// Milliseconds to wait before the panel is drawn. 0 = Windows parity (instant).
    /// A small value (~120) hides the panel entirely during fast back-and-forth toggling.
    var showDelayMs: Int = 0
    /// Render live window thumbnails. Purely additive: the panel never waits for them.
    var thumbnails: Bool = true
    /// Include windows that are currently minimized.
    var includeMinimized: Bool = true
    /// Include windows living on other Spaces.
    var includeOtherSpaces: Bool = true
    /// Include windows that are hidden because their app is hidden.
    var includeHiddenApps: Bool = true
    /// Max tiles per row before wrapping into a grid.
    var maxColumns: Int = 7
    /// Tile edge length in points.
    var tileSize: Double = 148
    /// Select the entry under the mouse pointer while the panel is open.
    var mouseHover: Bool = true
    /// Start Tappi when the user logs in.
    var launchAtLogin: Bool = false

    /// `~/Library/Application Support/Tappi`
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tappi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static let url: URL = directory.appendingPathComponent("settings.json")

    static func load() -> Settings {
        (try? loadFromDisk()) ?? Settings()
    }

    /// Throws instead of falling back to defaults, so a typo in a hand-edited file
    /// does not silently reset every setting.
    static func loadFromDisk() throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }

    /// Modification date of the file on disk, nil if it does not exist yet.
    static var fileModificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Settings.url, options: .atomic)
    }
}

/// Global mutable settings. Read from the main thread only.
final class SettingsStore {
    static let shared = SettingsStore()
    private(set) var value: Settings
    static let changed = Notification.Name("TappiSettingsChanged")

    /// Modification date of the file as last read or written by Tappi.
    private var knownModificationDate: Date?

    private init() {
        value = Settings.load()
        knownModificationDate = Settings.fileModificationDate
    }

    func mutate(_ body: (inout Settings) -> Void) {
        // Pick up hand edits first, otherwise saving would overwrite them.
        reloadIfChangedOnDisk()
        body(&value)
        value.save()
        knownModificationDate = Settings.fileModificationDate
        applyChange()
    }

    /// Re-reads settings.json if it was edited outside Tappi since the last read.
    /// A file that does not parse is ignored and logged; the current values stay.
    func reloadIfChangedOnDisk() {
        guard let date = Settings.fileModificationDate, date != knownModificationDate else { return }
        knownModificationDate = date
        do {
            value = try Settings.loadFromDisk()
            applyChange()
        } catch {
            NSLog("Tappi: settings.json could not be read, keeping current settings: \(error)")
        }
    }

    private func applyChange() {
        SystemSwitcher.apply()
        NotificationCenter.default.post(name: SettingsStore.changed, object: nil)
    }
}
