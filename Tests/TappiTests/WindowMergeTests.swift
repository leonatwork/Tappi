import XCTest
@testable import Tappi

final class WindowMergeTests: XCTestCase {
    private struct Values: Equatable {
        let title: String
        let frame: [Int]
        let isMinimized: Bool
    }

    private typealias Item = WindowMergeItem<String, Int, Values>

    private func window(_ key: String, pid: Int = 1, z: Int = 0,
                        title: String = "known", minimized: Bool = false) -> Item {
        Item(key: key, pid: pid, zIndex: z,
             value: Values(title: title, frame: [10, 20, 640, 480], isMinimized: minimized))
    }

    func testKnownWindowsKeepMRURankAndReceiveFreshValues() {
        let old = [window("a"), window("b")]
        let snapshot = [window("b", z: 0), window("a", z: 9, title: "changed", minimized: true)]

        let result = WindowMerge.merge(old: old, snapshot: snapshot,
                                       unresponsivePIDs: [], seeded: true)

        XCTAssertEqual(result.map(\.key), ["a", "b"])
        XCTAssertEqual(result[0].value, snapshot[1].value)
        XCTAssertEqual(old[0].value.title, "known", "Merging must not mutate its inputs")
    }

    func testNewWindowsAreAppendedInZOrder() {
        let result = WindowMerge.merge(
            old: [window("known", z: 50)],
            snapshot: [window("back", z: 7), window("known", z: 50), window("front", z: 0)],
            unresponsivePIDs: [], seeded: true)

        XCTAssertEqual(result.map(\.key), ["known", "front", "back"])
    }

    func testMissingWindowsOfRespondingAppsDisappear() {
        let result = WindowMerge.merge(
            old: [window("closed"), window("open")], snapshot: [window("open")],
            unresponsivePIDs: [], seeded: true)

        XCTAssertEqual(result.map(\.key), ["open"])
    }

    // AC-1: Every window of the timed-out app retains its position and last values.
    func testTimeoutKeepsAllWindowsAndLastKnownValues() {
        let old = [window("front", pid: 2), window("a", title: "last title", minimized: true),
                   window("middle", pid: 2), window("b")]
        let snapshot = [window("middle", pid: 2, z: 0), window("front", pid: 2, z: 1)]

        let result = WindowMerge.merge(old: old, snapshot: snapshot,
                                       unresponsivePIDs: [1], seeded: true)

        XCTAssertEqual(result.map(\.key), old.map(\.key))
        XCTAssertEqual(result[1].value, old[1].value)
        XCTAssertEqual(result[3].value, old[3].value)
    }

    // AC-2: Recovery updates the existing windows instead of appending them anew.
    func testRecoveryAfterRepeatedTimeoutsKeepsMRURank() {
        let old = [window("front", pid: 2), window("slow"), window("back", pid: 2)]
        let responding = [window("back", pid: 2), window("front", pid: 2)]
        let blocked = WindowMerge.merge(old: old, snapshot: responding,
                                        unresponsivePIDs: [1], seeded: true)
        let stillBlocked = WindowMerge.merge(old: blocked, snapshot: responding,
                                             unresponsivePIDs: [1], seeded: true)
        let recovered = WindowMerge.merge(
            old: stillBlocked, snapshot: responding + [window("slow", z: 99, title: "recovered")],
            unresponsivePIDs: [], seeded: true)

        XCTAssertEqual(recovered.map(\.key), ["front", "slow", "back"])
        XCTAssertEqual(recovered[1].value.title, "recovered")
    }

    func testTimeoutKeepsRankWhileNewWindowsAreAppendedInZOrder() {
        let result = WindowMerge.merge(
            old: [window("known", pid: 2), window("slow")],
            snapshot: [window("newBack", pid: 2, z: 8), window("known", pid: 2, z: 9),
                       window("newFront", pid: 3, z: 0)],
            unresponsivePIDs: [1], seeded: true)

        XCTAssertEqual(result.map(\.key), ["known", "slow", "newFront", "newBack"])
    }

    // AC-3: A successful empty response is not a timeout.
    func testSuccessfulEmptyResponseRemovesPreviouslyTimedOutWindows() {
        let blocked = WindowMerge.merge(old: [window("slow")], snapshot: [],
                                        unresponsivePIDs: [1], seeded: true)
        let result = WindowMerge.merge(old: blocked, snapshot: [],
                                       unresponsivePIDs: [], seeded: true)

        XCTAssertTrue(result.isEmpty)
    }

    // AC-4: Enumeration only reports unresponsive pids still in regularApps().
    func testTerminatedPIDIsRemovedAfterTimeout() {
        let old = [window("slow"), window("running", pid: 2)]
        let snapshot = [window("running", pid: 2)]
        let blocked = WindowMerge.merge(old: old, snapshot: snapshot,
                                        unresponsivePIDs: [1], seeded: true)
        let result = WindowMerge.merge(old: blocked, snapshot: snapshot,
                                       unresponsivePIDs: [], seeded: true)

        XCTAssertEqual(result.map(\.key), ["running"])
    }

    func testTerminationRemovalIsNotUndoneByAnInFlightTimeout() {
        let result = WindowMerge.merge(old: [window("running", pid: 2)],
                                       snapshot: [window("running", pid: 2)],
                                       unresponsivePIDs: [1], seeded: true)

        XCTAssertEqual(result.map(\.key), ["running"])
    }

    // AC-5: Missing replies do not affect the other apps' cold-start z-order.
    func testColdStartWithTimeoutSeedsFromZOrder() {
        let result = WindowMerge.merge(
            old: [Item](), snapshot: [window("back", pid: 2, z: 8), window("front", pid: 3, z: 1),
                                      window("offscreen", pid: 2, z: Int.max)],
            unresponsivePIDs: [1], seeded: false)

        XCTAssertEqual(result.map(\.key), ["front", "back", "offscreen"])
    }

    func testColdStartSortsKnownWindowsByFreshZOrderToo() {
        let result = WindowMerge.merge(
            old: [window("back"), window("front")],
            snapshot: [window("back", z: 8), window("front", z: 1)],
            unresponsivePIDs: [], seeded: false)

        XCTAssertEqual(result.map(\.key), ["front", "back"])
    }

    func testColdStartWithOnlyTimeoutsDoesNotInventWindows() {
        let result = WindowMerge.merge(old: [Item](), snapshot: [],
                                       unresponsivePIDs: [1], seeded: false)

        XCTAssertTrue(result.isEmpty)
    }
}
