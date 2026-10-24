import XCTest
@testable import Tappi

final class SessionSelectionTests: XCTestCase {
    func testRemovingEarlierTilesKeepsSelectedWindow() {
        XCTAssertEqual(SessionSelection.afterRemoving([0], selected: 2, remainingCount: 3), 1)
        XCTAssertEqual(SessionSelection.afterRemoving([0, 2], selected: 3, remainingCount: 2), 1)
    }

    func testRemovingSelectedTileUsesNextOrLastVisibleTile() {
        XCTAssertEqual(SessionSelection.afterRemoving([1], selected: 1, remainingCount: 3), 1)
        XCTAssertEqual(SessionSelection.afterRemoving([3], selected: 3, remainingCount: 3), 2)
    }

    func testEmptyListHasNoSelection() {
        XCTAssertNil(SessionSelection.afterRemoving([0, 1], selected: 1, remainingCount: 0))
    }
}
