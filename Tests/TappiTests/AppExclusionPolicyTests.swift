import XCTest
import CoreGraphics
@testable import Tappi

final class AppExclusionPolicyTests: XCTestCase {
    private func policy(_ apps: [String] = ["COM.EXAMPLE.Remote"]) -> AppExclusionPolicy {
        var settings = Settings()
        settings.passthroughApps = apps
        return AppExclusionPolicy(settings: settings)
    }

    func testPassthroughLeavesBothSwitchKeysAndDirectionsUnswallowed() {
        let policy = policy()
        for bundleID in ["com.example.remote", "COM.EXAMPLE.REMOTE", "com.Example.Remote"] {
            let front = AppExclusionPolicy.normalize(bundleID)
            for key in [KeyCode.tab] + Array(KeyCode.aboveTab) {
                for modifier in [HoldModifier.command, .option, .control] {
                    for extra in [CGEventFlags(), .maskShift, .maskControl] {
                        XCTAssertFalse(policy.shouldHandleKeyDown(
                            key, flags: modifier.flag.union(extra), modifier: modifier,
                            sessionActive: false, frontBundleID: front))
                    }
                }
            }
        }
    }

    func testOrdinaryAppRetainsShortcutRulesAndUnknownAppDoesNotMatch() {
        for front in ["com.example.other", nil] as [String?] {
            XCTAssertTrue(policy().shouldHandleKeyDown(
                KeyCode.tab, flags: .maskCommand, modifier: .command,
                sessionActive: false, frontBundleID: front))
            XCTAssertFalse(policy().shouldHandleKeyDown(
                KeyCode.tab, flags: [], modifier: .command,
                sessionActive: false, frontBundleID: front))
            XCTAssertFalse(policy().shouldHandleKeyDown(
                KeyCode.w, flags: .maskCommand, modifier: .command,
                sessionActive: false, frontBundleID: front))
        }
    }

    func testForegroundChangeDoesNotInterruptHoldingOrStickySession() {
        for key in [KeyCode.tab, KeyCode.escape, KeyCode.w] {
            XCTAssertTrue(policy().shouldHandleKeyDown(
                key, flags: [], modifier: .command,
                sessionActive: true, frontBundleID: "com.example.remote"))
        }
    }

    func testOrdinaryAppStillHandlesBothSwitchKeysWithEveryModifier() {
        for key in [KeyCode.tab] + Array(KeyCode.aboveTab) {
            for modifier in [HoldModifier.command, .option, .control] {
                XCTAssertTrue(policy().shouldHandleKeyDown(
                    key, flags: modifier.flag.union(.maskShift), modifier: modifier,
                    sessionActive: false, frontBundleID: "com.example.other"))
            }
        }
    }

    func testEveryPresetAppPassesThroughWithItsCachedBundleID() {
        let settings = Settings()
        let policy = AppExclusionPolicy(settings: settings)
        for bundleID in settings.passthroughApps {
            XCTAssertTrue(policy.passesThrough(frontBundleID: AppExclusionPolicy.normalize(bundleID)))
        }
    }

    func testUpdatedSettingsReplaceCachedMembershipAndListsAreIndependent() {
        XCTAssertTrue(policy().passesThrough(frontBundleID: "com.example.remote"))
        XCTAssertFalse(policy([]).passesThrough(frontBundleID: "com.example.remote"))
        var settings = Settings()
        settings.excludedApps = ["com.example.remote"]
        settings.passthroughApps = []
        XCTAssertFalse(AppExclusionPolicy(settings: settings).passesThrough(frontBundleID: "com.example.remote"))
    }

    func testSystemPolicyRestoresOnPassthroughAndSuppressesWhenOrdinaryAppReturns() {
        let settings = Settings()
        let policy = policy()
        XCTAssertFalse(policy.shouldSuppressSystemSwitcher(
            settings: settings, ready: true, frontBundleID: "com.example.remote"))
        XCTAssertTrue(policy.shouldSuppressSystemSwitcher(
            settings: settings, ready: true, frontBundleID: "com.example.other"))
        XCTAssertFalse(policy.shouldSuppressSystemSwitcher(
            settings: settings, ready: false, frontBundleID: "com.example.other"))
        var changed = settings
        changed.replaceSystemSwitcher = false
        XCTAssertFalse(policy.shouldSuppressSystemSwitcher(
            settings: changed, ready: true, frontBundleID: "com.example.other"))
        for modifier in [HoldModifier.option, .control] {
            changed = settings
            changed.holdModifier = modifier
            XCTAssertFalse(policy.shouldSuppressSystemSwitcher(
                settings: changed, ready: true, frontBundleID: "com.example.other"))
        }
    }
}
