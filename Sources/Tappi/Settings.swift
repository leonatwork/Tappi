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
    /// Modifier held down during a session.
    var holdModifier: HoldModifier = .option
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

    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tappi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }()

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
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

    private init() { value = Settings.load() }

    func mutate(_ body: (inout Settings) -> Void) {
        body(&value)
        value.save()
        NotificationCenter.default.post(name: SettingsStore.changed, object: nil)
    }
}
