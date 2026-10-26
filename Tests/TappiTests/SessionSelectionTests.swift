import XCTest
@testable import Tappi

final class SessionSelectionTests: XCTestCase {
    private final class Window: SessionWindow {
        let pid: Int32
        let bundleID: String?
        var isMinimized = false
        var isHidden = false
        var isOnActiveSpace = true

        init(pid: Int32, bundleID: String) {
            self.pid = pid
            self.bundleID = bundleID
        }
    }

    func testQuickTogglesUsePromotedMRUWhileForegroundNotificationIsPending() throws {
        let appA = Window(pid: 1, bundleID: "com.example.A")
        let appB = Window(pid: 2, bundleID: "com.example.B")
        let older = Window(pid: 3, bundleID: "com.example.Older")
        for initialEntries in [[appA, appB], [appA, appB, older]] {
            var entries = initialEntries
            var session = SwitcherSession()
            // No activation notification arrives between these commits.
            let frontPid = appA.pid
            for expected in [appB, appA, appB, appA] {
                let list = WindowSessionList.make(entries: entries, settings: Settings(),
                                                  scope: .allWindows, frontPid: frontPid)
                let included = SessionSelection.includesCurrentWindow(entries.first,
                                                                      firstCandidate: list.first)
                XCTAssertTrue(included)
                XCTAssertTrue(session.begin(count: list.count, backwards: false, sticky: false,
                                            currentWindowIncluded: included))
                let index = try XCTUnwrap(session.releaseModifier(count: list.count))
                XCTAssertTrue(list[index] === expected)
                MRUOrdering.promote(at: index, in: &entries)
                XCTAssertTrue(entries.first === expected)
            }
        }
    }

    func testExcludedMRUHeadStillSelectsFirstRemainingWindow() throws {
        let current = Window(pid: 1, bundleID: "com.example.Current")
        let previous = Window(pid: 2, bundleID: "com.example.Previous")
        let older = Window(pid: 3, bundleID: "com.example.Older")
        var settings = Settings()
        settings.excludedApps = ["COM.EXAMPLE.CURRENT"]
        for entries in [[current, previous], [current, previous, older]] {
            let list = WindowSessionList.make(entries: entries, settings: settings,
                                              scope: .allWindows, frontPid: current.pid)
            let included = SessionSelection.includesCurrentWindow(entries.first,
                                                                  firstCandidate: list.first)
            XCTAssertFalse(included)
            var session = SwitcherSession()
            XCTAssertTrue(session.begin(count: list.count, backwards: false, sticky: false,
                                        currentWindowIncluded: included))
            let index = try XCTUnwrap(session.releaseModifier(count: list.count))
            XCTAssertTrue(list[index] === previous)
        }
    }

    func testEmptyListDoesNotIncludeCurrentWindow() {
        XCTAssertFalse(SessionSelection.includesCurrentWindow(nil, firstCandidate: nil))
    }

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
