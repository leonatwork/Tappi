import XCTest
@testable import Tappi

final class SwitcherKeyMapTests: XCTestCase {
    func testQwertyQwertzAndColemakKeepTheLetterKeys() {
        let layouts: [[Int64: String]] = [
            [12: "q", 13: "w", 6: "z", 16: "y"],
            [12: "q", 13: "w", 6: "y", 16: "z"],
            [12: "q", 13: "w", 14: "f", 15: "p"]
        ]
        for characters in layouts {
            let map = SwitcherKeyMap(currentCharacters: characters)
            XCTAssertEqual(map[13], .closeWindow)
            XCTAssertEqual(map[12], .quitApp)
            XCTAssertNil(map[6])
            XCTAssertNil(map[14])
        }
    }

    func testAzertyUsesLabelledWAndQAndLeavesAAndZInert() {
        let map = SwitcherKeyMap(currentCharacters: [12: "a", 13: "z", 0: "q", 6: "w"])
        XCTAssertEqual(map[6], .closeWindow)
        XCTAssertEqual(map[0], .quitApp)
        XCTAssertNil(map[12])
        XCTAssertNil(map[13])
    }

    func testDvorakAndUppercaseLabels() {
        let map = SwitcherKeyMap(currentCharacters: [12: "'", 13: ",", 43: "W", 7: "Q"])
        XCTAssertEqual(map[43], .closeWindow)
        XCTAssertEqual(map[7], .quitApp)
        XCTAssertNil(map[12])
        XCTAssertNil(map[13])
    }

    func testAsciiLayoutIsUsedForLatinShortcuts() {
        let map = SwitcherKeyMap(currentCharacters: [12: "q", 13: "w"],
                                 asciiCharacters: [0: "q", 6: "w"])
        XCTAssertEqual(map[0], .quitApp)
        XCTAssertEqual(map[6], .closeWindow)
        XCTAssertNil(map[12])
        XCTAssertNil(map[13])
    }

    func testNonLatinLayoutUsesAnsiEvenIfLastAsciiLayoutWasDvorak() {
        let map = SwitcherKeyMap(currentCharacters: [12: "й", 13: "ц", 0: "ф"],
                                 asciiCharacters: [43: "w", 7: "q"])
        XCTAssertEqual(map[13], .closeWindow)
        XCTAssertEqual(map[12], .quitApp)
        XCTAssertNil(map[43])
        XCTAssertNil(map[7])
    }

    func testMissingLayoutDataAndIndividuallyMissingLettersFallBack() {
        let empty = SwitcherKeyMap(currentCharacters: [:])
        XCTAssertEqual(empty[13], .closeWindow)
        XCTAssertEqual(empty[12], .quitApp)
        let partial = SwitcherKeyMap(currentCharacters: [6: "w", 13: "z"])
        XCTAssertEqual(partial[6], .closeWindow)
        XCTAssertEqual(partial[12], .quitApp)
        XCTAssertNil(partial[13])
    }

    func testDeleteKeysAlwaysCloseAndOtherShortcutsCannotBeRemapped() {
        let map = SwitcherKeyMap(currentCharacters: [12: "q", 13: "w", 51: "q", 117: "q",
                                                    48: "w", 50: "w", 10: "q", 53: "q"])
        XCTAssertEqual(map[51], .closeWindow)
        XCTAssertEqual(map[117], .closeWindow)
        let unchangedKeys: [Int64] = [48, 50, 10, 53, 36, 49, 123, 124, 125, 126, -1, 128]
        for key in unchangedKeys {
            XCTAssertNil(map[key])
        }
    }

    func testRebuildingForLayoutChangeDoesNotRetainOldBindings() {
        var map = SwitcherKeyMap(currentCharacters: [12: "q", 13: "w"])
        map = SwitcherKeyMap(currentCharacters: [12: "a", 13: "z", 0: "q", 6: "w"])
        XCTAssertNil(map[12])
        XCTAssertNil(map[13])
        XCTAssertEqual(map[0], .quitApp)
        XCTAssertEqual(map[6], .closeWindow)
    }
}
