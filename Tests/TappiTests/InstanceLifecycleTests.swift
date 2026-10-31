import XCTest
@testable import Tappi

final class InstanceLifecycleTests: XCTestCase {
    func testOrdinarySecondInstanceExitsWithoutTakingOwnership() {
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: true, restartRemaining: nil), .exit)
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: nil), .start)
    }

    func testReplacementWaitsUntilOldInstanceHasExited() {
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: true, restartRemaining: 5), .wait)
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: true, restartRemaining: 0.01), .wait)
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: 3), .start)
    }

    func testTimeoutExitsOnlyReplacementWhileOldInstanceRemainsActive() {
        for remaining in [0.0, -0.01] {
            XCTAssertEqual(InstanceLifecycle.startup(hasPeer: true, restartRemaining: remaining), .exit)
            XCTAssertFalse(InstanceLifecycle.shouldTerminateForRestart(
                launchSucceeded: true, replacementReady: true,
                replacementRunning: true, remaining: remaining))
        }
    }

    func testOldInstanceExitingAtDeadlineDoesNotLeaveNoInstance() {
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: 0), .start)
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: -0.01), .start)
    }

    func testLaunchCallbackAloneDoesNotTerminateOldInstance() {
        XCTAssertFalse(InstanceLifecycle.shouldTerminateForRestart(
            launchSucceeded: true, replacementReady: false,
            replacementRunning: true, remaining: 4))
    }

    func testSuccessfulRestartHandsOwnershipToExactlyOneInstance() {
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: nil), .start)
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: true, restartRemaining: 4), .wait)
        XCTAssertFalse(InstanceLifecycle.shouldRestore(
            ownsLifecycle: false, suppressedByUs: false, force: true))
        XCTAssertTrue(InstanceLifecycle.shouldTerminateForRestart(
            launchSucceeded: true, replacementReady: true,
            replacementRunning: true, remaining: 3))
        XCTAssertTrue(InstanceLifecycle.shouldRestore(
            ownsLifecycle: true, suppressedByUs: true, force: false))
        XCTAssertEqual(InstanceLifecycle.startup(hasPeer: false, restartRemaining: 2), .start)
    }

    func testOnlyConfirmedLiveReplacementAllowsOldInstanceToTerminate() {
        XCTAssertTrue(InstanceLifecycle.shouldTerminateForRestart(
            launchSucceeded: true, replacementReady: true,
            replacementRunning: true, remaining: 4))
        XCTAssertFalse(InstanceLifecycle.shouldTerminateForRestart(
            launchSucceeded: false, replacementReady: true,
            replacementRunning: true, remaining: 4))
        XCTAssertFalse(InstanceLifecycle.shouldTerminateForRestart(
            launchSucceeded: true, replacementReady: true,
            replacementRunning: false, remaining: 4))
    }

    func testNonOwnerCannotRestoreEvenForForcedTerminationOrSignals() {
        for force in [false, true] {
            for suppressed in [false, true] {
                XCTAssertFalse(InstanceLifecycle.shouldRestore(
                    ownsLifecycle: false, suppressedByUs: suppressed, force: force))
            }
        }
    }

    func testOwnerCanRestoreItsSuppressionAndExplicitlyRepairOrphanedState() {
        XCTAssertTrue(InstanceLifecycle.shouldRestore(
            ownsLifecycle: true, suppressedByUs: true, force: false))
        XCTAssertFalse(InstanceLifecycle.shouldRestore(
            ownsLifecycle: true, suppressedByUs: false, force: false))
        XCTAssertTrue(InstanceLifecycle.shouldRestore(
            ownsLifecycle: true, suppressedByUs: false, force: true))
    }

    func testRestartArgumentsRoundTripWithoutDependingOnSettings() {
        let request = RestartRequest(token: UUID().uuidString, parentPID: 123, deadline: 456.5)
        XCTAssertEqual(RestartRequest(arguments: ["Tappi"] + request.arguments), request)
        XCTAssertNil(RestartRequest(arguments: ["Tappi"]))
    }

    func testMalformedRestartArgumentsAreNotAccepted() {
        let token = UUID().uuidString
        for suffix in [[], [token], [token, "123"], ["", "123", "456"],
                       ["../not-a-token", "123", "456"], [token, "0", "456"],
                       [token, "bad-pid", "456"], [token, "123", "nan"], [token, "123", "inf"]] {
            XCTAssertNil(RestartRequest(arguments: ["Tappi", RestartRequest.argument] + suffix))
        }
    }

    func testTimeoutWinningTheHandoverCannotBeAcceptedLater() throws {
        let request = RestartRequest(token: UUID().uuidString, parentPID: 123, deadline: 456.5)
        try request.prepare()
        defer { request.remove() }
        XCTAssertEqual(request.decide(.cancelled), .cancelled)
        XCTAssertEqual(request.decide(.accepted), .cancelled)
        XCTAssertEqual(request.waitDeadline, request.deadline)
    }

    func testAcceptanceWinningTheHandoverCannotBeCancelledAtDeadline() throws {
        let request = RestartRequest(token: UUID().uuidString, parentPID: 123, deadline: 456.5)
        try request.prepare()
        defer { request.remove() }
        XCTAssertEqual(request.decide(.accepted), .accepted)
        XCTAssertEqual(request.decide(.cancelled), .accepted)
        XCTAssertEqual(request.waitDeadline, request.deadline + RestartRequest.timeout)
    }

    func testMissingHandoverCannotAuthorizeOldInstanceToExit() {
        let request = RestartRequest(token: UUID().uuidString, parentPID: 123, deadline: 456.5)
        XCTAssertNil(request.decide(.accepted))
        XCTAssertFalse(request.announceReady())
    }

    func testReadinessRequiresPreparedHandoverAndIsIdempotent() throws {
        let request = RestartRequest(token: UUID().uuidString, parentPID: 123, deadline: 456.5)
        try request.prepare()
        defer { request.remove() }
        XCTAssertFalse(request.isReady)
        XCTAssertTrue(request.announceReady())
        XCTAssertTrue(request.isReady)
        XCTAssertTrue(request.announceReady())
    }
}
