import XCTest
@testable import Tappi

final class InterfaceLanguageTests: XCTestCase {
    func testSystemLanguageMatchesSupportedPreferences() {
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["de-DE", "en-US"]), .german)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["en-GB", "de"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR", "de-AT"]), .german)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR"]), .english)
    }

    func testExplicitLanguageOverridesSystemPreferences() {
        XCTAssertEqual(InterfaceLanguage.english.resolved(preferredLanguages: ["de"]), .english)
        XCTAssertEqual(InterfaceLanguage.german.resolved(preferredLanguages: ["en"]), .german)
        XCTAssertEqual(InterfaceLanguage.english.text("Language", "Sprache"), "Language")
        XCTAssertEqual(InterfaceLanguage.german.text("Language", "Sprache"), "Sprache")
    }

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

    func testLanguagePreferenceSurvivesSettingsRoundTrip() throws {
        for language in InterfaceLanguage.allCases {
            var settings = Settings()
            settings.language = language
            let data = try JSONEncoder().encode(settings)
            let restored = try JSONDecoder().decode(Settings.self, from: data)
            XCTAssertEqual(restored.language, language)
        }
    }
}
