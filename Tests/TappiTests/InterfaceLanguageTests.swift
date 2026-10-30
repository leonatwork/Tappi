import XCTest
@testable import Tappi

final class InterfaceLanguageTests: XCTestCase {
    /// The repository's `Resources` folder, which build.sh copies into the bundle.
    private let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TappiTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
        .appendingPathComponent("Resources", isDirectory: true)

    private func strings(_ language: InterfaceLanguage) throws -> [String: String] {
        let code = try XCTUnwrap(language.code)
        let url = resources.appendingPathComponent("\(code).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let table = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(table as? [String: String], "\(code) is not a strings table")
    }

    // MARK: - Choosing a language

    func testSystemLanguageMatchesSupportedPreferences() {
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["de-DE", "en-US"]), .german)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["en-GB", "de"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR", "de-AT"]), .french)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["es-MX"]), .spanish)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["it-IT"]), .italian)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["pt-BR"]), .portugueseBrazil)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["nl-NL"]), .dutch)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .japanese)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]), .chineseSimplified)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["ko-KR"]), .korean)
    }

    func testUnsupportedSystemLanguageFallsBackSensibly() {
        // The first supported entry in the list wins …
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["sv-SE", "it-IT"]), .italian)
        // … and with none at all, English.
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["sv-SE"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: []), .english)
    }

    func testExplicitLanguageOverridesSystemPreferences() {
        XCTAssertEqual(InterfaceLanguage.english.resolved(preferredLanguages: ["de"]), .english)
        XCTAssertEqual(InterfaceLanguage.german.resolved(preferredLanguages: ["en"]), .german)
        XCTAssertEqual(InterfaceLanguage.japanese.resolved(preferredLanguages: ["fr-FR"]), .japanese)
        for language in InterfaceLanguage.localized {
            XCTAssertEqual(language.resolved(preferredLanguages: ["ko-KR"]), language)
        }
    }

    func testEveryLanguageHasACodeAndItsOwnName() {
        XCTAssertNil(InterfaceLanguage.system.code)
        XCTAssertNil(InterfaceLanguage.system.nativeName)
        XCTAssertEqual(InterfaceLanguage.localized.compactMap(\.code),
                       ["en", "de", "fr", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko"])
        XCTAssertEqual(InterfaceLanguage.localized.compactMap(\.nativeName),
                       ["English", "Deutsch", "Français", "Español", "Italiano", "Português (Brasil)",
                        "Nederlands", "日本語", "简体中文", "한국어"])
        for language in InterfaceLanguage.localized {
            XCTAssertEqual(InterfaceLanguage(code: language.code!), language)
        }
        XCTAssertNil(InterfaceLanguage(code: "sv"))
    }

    // MARK: - settings.json

    func testOlderSettingsKeepExistingPreferences() throws {
        var original = Settings()
        original.holdModifier = .option
        original.tileSize = 240
        original.thumbnails = false
        original.showDelayMs = 120
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["language"])

        let restored = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertNil(restored.language)
        XCTAssertEqual(restored.holdModifier, .option)
        XCTAssertEqual(restored.tileSize, 240)
        XCTAssertFalse(restored.thumbnails)
        XCTAssertEqual(restored.showDelayMs, 120)
    }

    /// Decodes a settings file whose `language` key holds `value`.
    private func decodeSettings(language value: String) throws -> Settings {
        let data = try JSONEncoder().encode(Settings())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["language"] = value
        return try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testSettingsWrittenBeforeMoreLanguagesStillDecode() throws {
        // Tappi 1.1 wrote exactly these three values.
        XCTAssertEqual(try decodeSettings(language: "english").language, .english)
        XCTAssertEqual(try decodeSettings(language: "german").language, .german)
        XCTAssertEqual(try decodeSettings(language: "system").language, .system)
    }

    func testEnglishAndGermanAreStillWrittenAsBefore() throws {
        // Going back to 1.1 must keep working for the two languages it knows.
        let expected: [(InterfaceLanguage, String)] = [(.english, "english"), (.german, "german"), (.system, "system")]
        for (language, stored) in expected {
            var settings = Settings()
            settings.language = language
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            XCTAssertEqual(json["language"] as? String, stored)
        }
    }

    func testHandEditedLanguageCodesAreAccepted() throws {
        XCTAssertEqual(try decodeSettings(language: "de").language, .german)
        XCTAssertEqual(try decodeSettings(language: "pt-BR").language, .portugueseBrazil)
        XCTAssertEqual(try decodeSettings(language: "zh-hans").language, .chineseSimplified)
    }

    func testUnknownLanguageFallsBackToSystemInsteadOfFailing() throws {
        let settings = try decodeSettings(language: "klingon")
        XCTAssertEqual(settings.language, .system)
    }

    func testLanguagePreferenceSurvivesSettingsRoundTrip() throws {
        for language in InterfaceLanguage.allCases {
            var settings = Settings()
            settings.language = language
            let data = try JSONEncoder().encode(settings)
            let restored = try JSONDecoder().decode(Settings.self, from: data)
            XCTAssertEqual(restored.language, language)
        }
    }

    // MARK: - Strings

    func testQuitConfirmationHintExistsInAllTenLanguages() throws {
        for language in InterfaceLanguage.localized {
            let hint = try XCTUnwrap(strings(language)["switcher.quitConfirmation"])
            XCTAssertFalse(hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(hint.contains("Q"), "The confirmation key must be visible in every language")
            let localizer = Localizer(language: language, resources: resources)
            XCTAssertEqual(localizer.string("switcher.quitConfirmation"), hint)
        }
    }

    func testEveryLanguageHasEveryKey() throws {
        let english = try strings(.english)
        XCTAssertFalse(english.isEmpty)
        for language in InterfaceLanguage.localized where language != .english {
            let table = try strings(language)
            XCTAssertEqual(Set(table.keys), Set(english.keys), "\(language.code!) differs from en")
            for (key, value) in table {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language.code!): \(key)")
            }
        }
    }

    func testLocalizerUsesTheChosenTable() {
        let german = Localizer(language: .german, resources: resources)
        XCTAssertEqual(german.string("menu.language"), "Sprache")
        XCTAssertEqual(german.string("menu.grantScreenRecording"), "Bildschirmaufnahme freigeben …")

        let japanese = Localizer(language: .japanese, resources: resources)
        XCTAssertEqual(japanese.string("menu.language"), "言語")

        let english = Localizer(language: .english, resources: resources)
        XCTAssertEqual(english.string("menu.language"), "Language")
    }

    func testLocalizerFollowsSystemPreferences() {
        let localizer = Localizer(language: .system, preferredLanguages: ["ko-KR"], resources: resources)
        XCTAssertEqual(localizer.language, .korean)
        XCTAssertEqual(localizer.string("menu.language"), "언어")

        let fallback = Localizer(language: .system, preferredLanguages: ["sv-SE"], resources: resources)
        XCTAssertEqual(fallback.string("menu.language"), "Language")
    }

    func testLocalizerFormatsArguments() {
        let french = Localizer(language: .french, resources: resources)
        XCTAssertEqual(french.string("status.active.other", arguments: ["⌘", 12, ""]), "Actif · ⌘Tab · 12 fenêtres")
        let english = Localizer(language: .english, resources: resources)
        XCTAssertEqual(english.string("status.active.one", arguments: ["⌥", 1, " · without previews"]),
                       "Active · ⌥Tab · 1 window · without previews")
    }

    func testMissingKeysAndMissingResourcesDegradeToTheKey() {
        let german = Localizer(language: .german, resources: resources)
        XCTAssertEqual(german.string("no.such.key"), "no.such.key")

        let bare = Localizer(language: .german, resources: nil)
        XCTAssertEqual(bare.string("menu.language"), "menu.language")
    }
}
