import XCTest
@testable import Tappi

final class SettingsTests: XCTestCase {
    private let completeJSON = """
    {
        "language": "german",
        "holdModifier": "option",
        "replaceSystemSwitcher": false,
        "showDelayMs": 120,
        "thumbnails": false,
        "includeMinimized": false,
        "includeOtherSpaces": false,
        "includeHiddenApps": false,
        "maxColumns": 5,
        "tileSize": 240,
        "mouseHover": false,
        "launchAtLogin": true,
        "excludedApps": ["com.example.Hidden"],
        "passthroughApps": ["com.example.Remote"]
    }
    """

    private var completeSettings: Settings {
        var settings = Settings()
        settings.language = .german
        settings.holdModifier = .option
        settings.replaceSystemSwitcher = false
        settings.showDelayMs = 120
        settings.thumbnails = false
        settings.includeMinimized = false
        settings.includeOtherSpaces = false
        settings.includeHiddenApps = false
        settings.maxColumns = 5
        settings.tileSize = 240
        settings.mouseHover = false
        settings.launchAtLogin = true
        settings.excludedApps = ["com.example.Hidden"]
        settings.passthroughApps = ["com.example.Remote"]
        return settings
    }

    /// Each case resets only the edited field, so equality checks all the others.
    private var fields: [(key: String, reset: (inout Settings) -> Void)] {
        let defaults = Settings()
        return [
            ("language", { $0.language = defaults.language }),
            ("holdModifier", { $0.holdModifier = defaults.holdModifier }),
            ("replaceSystemSwitcher", { $0.replaceSystemSwitcher = defaults.replaceSystemSwitcher }),
            ("showDelayMs", { $0.showDelayMs = defaults.showDelayMs }),
            ("thumbnails", { $0.thumbnails = defaults.thumbnails }),
            ("includeMinimized", { $0.includeMinimized = defaults.includeMinimized }),
            ("includeOtherSpaces", { $0.includeOtherSpaces = defaults.includeOtherSpaces }),
            ("includeHiddenApps", { $0.includeHiddenApps = defaults.includeHiddenApps }),
            ("maxColumns", { $0.maxColumns = defaults.maxColumns }),
            ("tileSize", { $0.tileSize = defaults.tileSize }),
            ("mouseHover", { $0.mouseHover = defaults.mouseHover }),
            ("launchAtLogin", { $0.launchAtLogin = defaults.launchAtLogin }),
            ("excludedApps", { $0.excludedApps = defaults.excludedApps }),
            ("passthroughApps", { $0.passthroughApps = defaults.passthroughApps })
        ]
    }

    private func completeObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(completeJSON.utf8)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testCompleteFilePreservesEveryField() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data(completeJSON.utf8)), completeSettings)
    }

    func testEmptyObjectUsesDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)), Settings())
    }

    func testEachMissingKeyDefaultsOnlyThatField() throws {
        for field in fields {
            var object = try completeObject()
            object.removeValue(forKey: field.key)
            var expected = completeSettings
            field.reset(&expected)
            XCTAssertEqual(try decode(object), expected, "Missing \(field.key)")
        }
    }

    func testEachInvalidValueDefaultsOnlyThatField() throws {
        for field in fields {
            var object = try completeObject()
            // Wrong scalar type for language, unknown enum case for the modifier,
            // and a string instead of a boolean or number for the remaining keys.
            object[field.key] = "yes"
            if field.key == "language" { object[field.key] = 42 }
            if field.key == "holdModifier" { object[field.key] = "alt" }
            var expected = completeSettings
            field.reset(&expected)
            XCTAssertEqual(try decode(object), expected, "Invalid \(field.key)")

            object[field.key] = ["unexpected": true]
            XCTAssertEqual(try decode(object), expected, "Object instead of \(field.key)")
        }
    }

    func testEachNullValueDefaultsOnlyThatField() throws {
        for field in fields {
            var object = try completeObject()
            object[field.key] = NSNull()
            var expected = completeSettings
            field.reset(&expected)
            XCTAssertEqual(try decode(object), expected, "Null \(field.key)")
        }
    }

    func testUnknownKeysAreIgnored() throws {
        var object = try completeObject()
        object["futureSetting"] = ["enabled": true, "values": [1, 2, 3]]
        XCTAssertEqual(try decode(object), completeSettings)
    }

    func testUnknownLanguageStillFallsBackToSystem() throws {
        var object = try completeObject()
        object["language"] = "klingon"
        var expected = completeSettings
        expected.language = .system
        XCTAssertEqual(try decode(object), expected)
    }

    func testRoundTripPreservesEveryField() throws {
        for settings in [Settings(), completeSettings] {
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
        }
    }

    func testInvalidDocumentStillThrows() {
        for json in ["{", "[]", "null", "42", "\"settings\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: Data(json.utf8)), json)
        }
    }

    func testLegacyFilePreservesSettingsAndSuppliesAppListDefaults() throws {
        var object = try completeObject()
        object.removeValue(forKey: "excludedApps")
        object.removeValue(forKey: "passthroughApps")
        var expected = completeSettings
        expected.excludedApps = []
        expected.passthroughApps = [
            "com.microsoft.rdc.macos", "com.parallels.desktop.console",
            "com.vmware.fusion", "com.utmapp.UTM", "com.citrix.receiver.icaviewer.mac"
        ]
        XCTAssertEqual(try decode(object), expected)
    }

    func testEmptyAppListsOverrideDefaults() throws {
        var object = try completeObject()
        object["excludedApps"] = [String]()
        object["passthroughApps"] = [String]()
        var expected = completeSettings
        expected.excludedApps = []
        expected.passthroughApps = []
        XCTAssertEqual(try decode(object), expected)
    }

    func testInvalidArrayElementDefaultsOnlyItsList() throws {
        for field in fields where field.key == "excludedApps" || field.key == "passthroughApps" {
            var object = try completeObject()
            object[field.key] = ["com.example.Valid", 42] as [Any]
            var expected = completeSettings
            field.reset(&expected)
            XCTAssertEqual(try decode(object), expected)
        }
    }
}
