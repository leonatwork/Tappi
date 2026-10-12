import Foundation

/// The language Tappi's own interface is shown in.
///
/// The raw values are what `settings.json` stores. `english` and `german` predate
/// the other languages and must keep decoding exactly as before, so the raw values
/// are names rather than locale codes.
enum InterfaceLanguage: String, CaseIterable, Codable {
    case system
    case english
    case german
    case french
    case spanish
    case italian
    case portugueseBrazil
    case dutch
    case japanese
    case chineseSimplified
    case korean

    /// Every language that ships a `.lproj` folder, development language first.
    static let localized: [InterfaceLanguage] = allCases.filter { $0 != .system }

    /// Name of the `.lproj` folder; nil for `.system`, which picks one at runtime.
    var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .german: return "de"
        case .french: return "fr"
        case .spanish: return "es"
        case .italian: return "it"
        case .portugueseBrazil: return "pt-BR"
        case .dutch: return "nl"
        case .japanese: return "ja"
        case .chineseSimplified: return "zh-Hans"
        case .korean: return "ko"
        }
    }

    /// The language's name in that language, as the Language submenu shows it.
    /// Deliberately not translated: someone stuck in a language they cannot read
    /// still has to recognise their own.
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portugueseBrazil: return "Português (Brasil)"
        case .dutch: return "Nederlands"
        case .japanese: return "日本語"
        case .chineseSimplified: return "简体中文"
        case .korean: return "한국어"
        }
    }

    init?(code: String) {
        guard let match = InterfaceLanguage.localized.first(where: {
            $0.code?.caseInsensitiveCompare(code) == .orderedSame
        }) else { return nil }
        self = match
    }

    /// A concrete language: `.system` becomes the best match for the macOS
    /// preferred languages, English if none of them is supported.
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        guard self == .system else { return self }
        let codes = InterfaceLanguage.localized.compactMap(\.code)
        guard let best = Bundle.preferredLocalizations(from: codes, forPreferences: preferredLanguages).first,
              let language = InterfaceLanguage(code: best) else { return .english }
        return language
    }

    // MARK: - Codable

    /// Accepts the stored names, and locale codes like `"de"` or `"pt-BR"` for
    /// hand-edited files. An unknown value (a typo, or a language added by a newer
    /// Tappi) means `.system` rather than a file that fails to load and takes every
    /// other setting down with it.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InterfaceLanguage(rawValue: raw) ?? InterfaceLanguage(code: raw) ?? .system
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Looks strings up in `Resources/<code>.lproj/Localizable.strings`.
///
/// The table is picked explicitly instead of through `NSLocalizedString`, because
/// the language is a Tappi setting that may differ from the system language and
/// changes without a restart.
struct Localizer {
    /// Always concrete, never `.system`.
    let language: InterfaceLanguage
    /// Directory containing the `.lproj` folders.
    let resources: URL?

    init(language: InterfaceLanguage,
         preferredLanguages: [String] = Locale.preferredLanguages,
         resources: URL? = Bundle.main.resourceURL) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
        self.resources = resources
    }

    private func table(_ language: InterfaceLanguage) -> Bundle? {
        guard let code = language.code,
              let url = resources?.appendingPathComponent("\(code).lproj", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Bundle(url: url)
    }

    /// The string for `key`; English if this language lacks it, the key itself if
    /// English lacks it too (e.g. a bare `swift run` outside the app bundle).
    func string(_ key: String, arguments: [CVarArg] = []) -> String {
        let english = table(.english)?.localizedString(forKey: key, value: key, table: nil) ?? key
        var format = english
        if language != .english, let own = table(language) {
            format = own.localizedString(forKey: key, value: english, table: nil)
        }
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}

/// The string for `key` in the interface language currently set.
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    Localizer(language: SettingsStore.shared.value.language ?? .system).string(key, arguments: arguments)
}
