import XCTest
@testable import Tappi

final class SwitcherSessionTests: XCTestCase {
    func testQuickReleaseSelectsPreviousWindowAndRepeatedToggleReturnsToCurrent() throws {
        var entries = ["current", "previous", "older"]
        var session = SwitcherSession()

        for expected in ["previous", "current"] {
            XCTAssertTrue(session.begin(count: entries.count, backwards: false, sticky: false))
            XCTAssertEqual(session.state, .holding)
            XCTAssertEqual(session.selection, 1)
            let index = try XCTUnwrap(session.releaseModifier(count: entries.count))
            XCTAssertEqual(entries[index], expected)
            MRUOrdering.promote(at: index, in: &entries)
            XCTAssertEqual(entries[0], expected)
            XCTAssertEqual(session.state, .idle)
            XCTAssertEqual(session.selection, 0)
        }
        XCTAssertEqual(entries, ["current", "previous", "older"])
    }

    func testCyclingKeepsMRUUntilReleaseAndPromotionPreservesOtherRanks() throws {
        var entries = ["current", "previous", "older", "oldest"]
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: entries.count, backwards: false, sticky: false))
        session.step(1, count: entries.count)
        session.step(1, count: entries.count)
        XCTAssertEqual(session.selection, 3)
        XCTAssertEqual(entries, ["current", "previous", "older", "oldest"])

        let index = try XCTUnwrap(session.releaseModifier(count: entries.count))
        MRUOrdering.promote(at: index, in: &entries)
        XCTAssertEqual(entries, ["oldest", "current", "previous", "older"])
        XCTAssertNil(session.commit(count: entries.count), "A session can commit only once")
    }

    func testShiftStartsAtEndAndCyclingWrapsBothWays() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 4, backwards: true, sticky: false))
        XCTAssertEqual(session.selection, 3)
        session.step(1, count: 4)
        XCTAssertEqual(session.selection, 0)
        session.step(-1, count: 4)
        XCTAssertEqual(session.selection, 3)
        session.step(-1, count: 4)
        XCTAssertEqual(session.selection, 2)
    }

    func testEscapeCancelsWithoutReturningAFocusTargetOrChangingMRU() {
        let entries = ["current", "previous", "older"]
        for sticky in [false, true] {
            var session = SwitcherSession()
            XCTAssertTrue(session.begin(count: entries.count, backwards: false, sticky: sticky))
            session.step(1, count: entries.count)
            session.cancel()
            XCTAssertEqual(session.state, .idle)
            XCTAssertEqual(session.selection, 0)
            XCTAssertNil(session.releaseModifier(count: entries.count))
            XCTAssertNil(session.commit(count: entries.count))
            XCTAssertEqual(entries, ["current", "previous", "older"])
        }
    }

    func testStickySessionSurvivesReleaseAndExplicitCommitSelectsCurrentTile() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 3, backwards: false, sticky: true))
        XCTAssertNil(session.releaseModifier(count: 3))
        XCTAssertEqual(session.state, .sticky)
        session.step(1, count: 3)
        XCTAssertEqual(session.commit(count: 3), 2)
        XCTAssertEqual(session.state, .idle)
    }

    func testEmptyAndSingleWindowSessionsDoNotStart() {
        for count in [0, 1] {
            for backwards in [false, true] {
                for sticky in [false, true] {
                    var session = SwitcherSession()
                    XCTAssertFalse(session.begin(count: count, backwards: backwards, sticky: sticky))
                    XCTAssertEqual(session.state, .idle)
                    session.step(1, count: count)
                    XCTAssertNil(session.commit(count: count))
                }
            }
        }
    }

    func testExcludedCurrentWindowDoesNotSkipFirstRemainingCandidate() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 3, backwards: false, sticky: false,
                                    currentWindowIncluded: false))
        XCTAssertEqual(session.releaseModifier(count: 3), 0)
        XCTAssertTrue(session.begin(count: 3, backwards: true, sticky: false,
                                    currentWindowIncluded: false))
        XCTAssertEqual(session.releaseModifier(count: 3), 2)
    }

    func testSingleRemainingCandidateCanBeSelectedWhenCurrentWindowIsExcluded() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 1, backwards: false, sticky: false,
                                    currentWindowIncluded: false))
        XCTAssertEqual(session.releaseModifier(count: 1), 0)
        XCTAssertFalse(session.begin(count: 0, backwards: false, sticky: false,
                                     currentWindowIncluded: false))
        XCTAssertEqual(session.state, .idle)
    }

    func testSelectionUsesDisplayedMRUPrefixWithoutChangingSingleWindowRule() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 10, backwards: true, sticky: false, capacity: 3))
        XCTAssertEqual(session.selection, 2)
        session.step(1, count: 3)
        XCTAssertEqual(session.selection, 0)
        XCTAssertEqual(session.commit(count: 3), 0)

        // Existing overflow behavior: multiple candidates may fit only one tile.
        XCTAssertTrue(session.begin(count: 10, backwards: false, sticky: false, capacity: 1))
        XCTAssertEqual(session.selection, 0)
        XCTAssertEqual(session.commit(count: 1), 0)
        XCTAssertFalse(session.begin(count: 10, backwards: false, sticky: false, capacity: 0))
        XCTAssertEqual(session.state, .idle)
    }

    func testMouseSelectionAndRemovedSelectionUseTheSameCommitPath() {
        var session = SwitcherSession()
        XCTAssertTrue(session.begin(count: 4, backwards: false, sticky: true))
        session.selection = 3
        session.selection = SessionSelection.afterRemoving([0], selected: session.selection,
                                                           remainingCount: 3) ?? 0
        XCTAssertEqual(session.commit(count: 3), 2)

        XCTAssertTrue(session.begin(count: 3, backwards: false, sticky: false))
        session.selection = 9
        XCTAssertNil(session.commit(count: 3))
        XCTAssertEqual(session.state, .idle)
    }

    func testPromotingCurrentOrInvalidIndexDoesNotChangeMRU() {
        var entries = ["current", "previous", "older"]
        for index in [0, -1, entries.count] {
            MRUOrdering.promote(at: index, in: &entries)
            XCTAssertEqual(entries, ["current", "previous", "older"])
        }
    }
}
