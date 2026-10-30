import XCTest
@testable import Tappi

final class QuitConfirmationTests: XCTestCase {
    func testOnlySecondPressForTheSameWindowQuitsAndConsumesConfirmation() {
        var confirmation = QuitConfirmation<String>()
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
        XCTAssertTrue(confirmation.isPending)
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .quit)
        XCTAssertFalse(confirmation.isPending)
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
    }

    func testChangedWindowIsAlwaysAFirstPressEvenWithinTheSameApp() {
        var confirmation = QuitConfirmation<String>()
        XCTAssertEqual(confirmation.handle(.quit(target: "app-a/window-1", isRepeat: false)), .showHint)
        XCTAssertEqual(confirmation.handle(.quit(target: "app-a/window-2", isRepeat: false)), .showHint)
        XCTAssertEqual(confirmation.handle(.quit(target: "app-a/window-2", isRepeat: false)), .quit)
    }

    func testOtherKeysSelectionChangeAndSessionEndDiscardTheRequest() {
        let interruptions: [QuitConfirmation<String>.Event] = [
            .otherKey, .selectionChanged("window-b"), .selectionChanged(nil), .sessionEnded
        ]
        for interruption in interruptions {
            var confirmation = QuitConfirmation<String>()
            XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
            XCTAssertEqual(confirmation.handle(interruption), .none)
            XCTAssertFalse(confirmation.isPending)
            XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
        }
    }

    func testHoveringTheSameSelectionDoesNotDiscardConfirmation() {
        var confirmation = QuitConfirmation<String>()
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
        XCTAssertEqual(confirmation.handle(.selectionChanged("window-a")), .none)
        XCTAssertTrue(confirmation.isPending)
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .quit)
    }

    func testKeyRepeatCannotArmOrConfirmQuit() {
        var confirmation = QuitConfirmation<String>()
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: true)), .none)
        XCTAssertFalse(confirmation.isPending)
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
        for _ in 0..<10 {
            XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: true)), .none)
            XCTAssertTrue(confirmation.isPending)
        }
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .quit)
    }

    func testMissingSelectionCannotArmOrConfirmQuit() {
        var confirmation = QuitConfirmation<String>()
        XCTAssertEqual(confirmation.handle(.quit(target: nil, isRepeat: false)), .none)
        XCTAssertFalse(confirmation.isPending)
        XCTAssertEqual(confirmation.handle(.quit(target: "window-a", isRepeat: false)), .showHint)
        XCTAssertEqual(confirmation.handle(.quit(target: nil, isRepeat: false)), .none)
        XCTAssertFalse(confirmation.isPending)
    }
}
