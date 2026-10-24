import AppKit
import ApplicationServices
import XCTest
@testable import Tappi

final class AppExclusionTests: XCTestCase {
    private func entry(_ title: String, pid: pid_t, bundleID: String?) -> WindowEntry {
        WindowEntry(axWindow: AXUIElementCreateApplication(pid), pid: pid,
                    title: title, appName: title, icon: nil, isMinimized: false,
                    isHidden: false, isOnActiveSpace: true, frame: nil,
                    cgWindowID: nil, bundleID: bundleID)
    }

    func testExclusionAppliesToBothScopesWithoutChangingMRU() {
        let entries = [entry("first", pid: 1, bundleID: "COM.EXAMPLE.HIDDEN"),
                       entry("second", pid: 2, bundleID: "com.example.Visible"),
                       entry("third", pid: 1, bundleID: "com.example.hidden"),
                       entry("unknown", pid: 3, bundleID: nil)]
        var settings = Settings()
        settings.excludedApps = ["Com.Example.Hidden"]
        func titles(_ scope: SwitchScope) -> [String] {
            WindowStore.sessionList(entries: entries, scope: scope, settings: settings,
                                    frontPid: 1, excludedBundleIDs: AppRules.normalized(settings.excludedApps))
                .map(\.title)
        }
        XCTAssertEqual(titles(.allWindows), ["second", "unknown"])
        XCTAssertEqual(titles(.currentApp), [])
        XCTAssertEqual(entries.map(\.title), ["first", "second", "third", "unknown"])
        settings.excludedApps = []
        XCTAssertEqual(titles(.allWindows), ["first", "second", "third", "unknown"])
        XCTAssertEqual(titles(.currentApp), ["first", "third"])
    }

    func testExcludedCurrentWindowAllowsSwitchingToSingleRemainingWindow() {
        let current = entry("current", pid: 1, bundleID: "COM.EXAMPLE.HIDDEN")
        let target = entry("target", pid: 2, bundleID: "com.example.visible")
        let entries = [current, target]
        let list = WindowStore.sessionList(entries: entries, scope: .allWindows,
            settings: Settings(), frontPid: 1,
            excludedBundleIDs: AppRules.normalized(["Com.Example.Hidden"]))

        XCTAssertEqual(list.map(\.title), ["target"])
        for backwards in [false, true] {
            XCTAssertEqual(SwitcherController.initialSelection(in: list,
                currentWindow: entries.first, backwards: backwards), 0)
        }
        XCTAssertEqual(entries.map(\.title), ["current", "target"])
    }

    func testExcludedCurrentWindowSelectsFirstTargetForwardAndLastBackward() {
        let current = entry("current", pid: 1, bundleID: "com.example.hidden")
        let entries = [current,
                       entry("previous", pid: 2, bundleID: "com.example.visible"),
                       entry("oldest", pid: 3, bundleID: "com.example.other")]
        let list = WindowStore.sessionList(entries: entries, scope: .allWindows,
            settings: Settings(), frontPid: 1,
            excludedBundleIDs: AppRules.normalized(["com.example.hidden"]))

        XCTAssertEqual(SwitcherController.initialSelection(in: list,
            currentWindow: entries.first, backwards: false), 0)
        XCTAssertEqual(SwitcherController.initialSelection(in: list,
            currentWindow: entries.first, backwards: true), 1)
        XCTAssertEqual(entries.map(\.title), ["current", "previous", "oldest"])

        let restored = WindowStore.sessionList(entries: entries, scope: .allWindows,
            settings: Settings(), frontPid: 1, excludedBundleIDs: [])
        XCTAssertEqual(SwitcherController.initialSelection(in: restored,
            currentWindow: entries.first, backwards: false), 1)
        XCTAssertEqual(SwitcherController.initialSelection(in: restored,
            currentWindow: entries.first, backwards: true), 2)
    }

    func testSessionDoesNotStartWithoutAnAlternativeWindow() {
        let current = entry("current", pid: 1, bundleID: "com.example.hidden")
        let scoped = WindowStore.sessionList(entries: [current], scope: .currentApp,
            settings: Settings(), frontPid: 1,
            excludedBundleIDs: AppRules.normalized(["com.example.hidden"]))
        for backwards in [false, true] {
            XCTAssertNil(SwitcherController.initialSelection(in: scoped,
                currentWindow: current, backwards: backwards))
            XCTAssertNil(SwitcherController.initialSelection(in: [current],
                currentWindow: current, backwards: backwards))
            XCTAssertNil(SwitcherController.initialSelection(in: [],
                currentWindow: nil, backwards: backwards))
        }
    }

    func testExclusionComposesWithExistingWindowFilters() {
        let minimized = entry("minimized", pid: 1, bundleID: "com.example.Visible")
        minimized.isMinimized = true
        let hidden = entry("hidden", pid: 1, bundleID: "com.example.Visible")
        hidden.isHidden = true
        let otherSpace = entry("otherSpace", pid: 1, bundleID: "com.example.Visible")
        otherSpace.isOnActiveSpace = false
        var settings = Settings()
        settings.includeMinimized = false
        settings.includeHiddenApps = false
        settings.includeOtherSpaces = false
        XCTAssertTrue(WindowStore.sessionList(entries: [minimized, hidden, otherSpace],
                                              scope: .allWindows, settings: settings,
                                              frontPid: 1, excludedBundleIDs: []).isEmpty)
    }

    func testTapPassesBothShortcutsThroughCaseInsensitivelyForEveryModifier() {
        let apps = AppRules.normalized(["Com.Example.Remote"])
        for modifier in [HoldModifier.command, .option, .control] {
            for key in [KeyCode.tab, 50, 10] {
                for extra in [CGEventFlags(), .maskShift, .maskControl] {
                    let flags = modifier.flag.union(extra)
                    XCTAssertFalse(AppRules.shouldHandleKeyDown(keyCode: key, flags: flags,
                        modifier: modifier, sessionActive: false,
                        frontmostBundleID: AppRules.normalizedBundleID("COM.EXAMPLE.Remote"),
                        passthroughBundleIDs: apps))
                    for front in [nil, "com.example.other"] as [String?] {
                        XCTAssertTrue(AppRules.shouldHandleKeyDown(keyCode: key, flags: flags,
                            modifier: modifier, sessionActive: false,
                            frontmostBundleID: front, passthroughBundleIDs: apps))
                    }
                }
            }
        }
    }

    func testBundleIDNormalizationHandlesCaseDuplicatesAndMissingIDs() {
        XCTAssertEqual(AppRules.normalized(["COM.EXAMPLE.Remote", "com.example.remote"]),
                       ["com.example.remote"])
        XCTAssertEqual(AppRules.normalizedBundleID("COM.EXAMPLE.Remote"), "com.example.remote")
        XCTAssertNil(AppRules.normalizedBundleID(nil))
    }

    func testTapKeepsActiveSessionAndIgnoresUnrelatedIdleKeys() {
        let apps = AppRules.normalized(["com.example.remote"])
        for key in [KeyCode.tab, KeyCode.escape, KeyCode.w] {
            XCTAssertTrue(AppRules.shouldHandleKeyDown(keyCode: key, flags: [],
                modifier: .command, sessionActive: true,
                frontmostBundleID: "com.example.remote", passthroughBundleIDs: apps))
        }
        for (key, flags) in [(KeyCode.tab, CGEventFlags()), (KeyCode.w, .maskCommand)] {
            XCTAssertFalse(AppRules.shouldHandleKeyDown(keyCode: key, flags: flags,
                modifier: .command, sessionActive: false,
                frontmostBundleID: nil, passthroughBundleIDs: []))
        }
    }

    func testSystemSuppressionTracksFrontmostAppAndReadiness() {
        var settings = Settings()
        let apps = AppRules.normalized(["Com.Example.Remote"])
        func suppress(_ front: String?, ready: Bool = true) -> Bool {
            SystemSwitcher.shouldSuppress(settings: settings, ready: ready,
                frontmostBundleID: front, passthroughBundleIDs: apps)
        }
        XCTAssertFalse(suppress("com.example.remote"))
        XCTAssertTrue(suppress("com.example.other"))
        XCTAssertFalse(suppress("com.example.remote"))
        XCTAssertFalse(suppress(nil, ready: false))
        XCTAssertTrue(suppress(nil))
        settings.replaceSystemSwitcher = false
        XCTAssertFalse(suppress("com.example.other"))
        settings.replaceSystemSwitcher = true
        for modifier in [HoldModifier.option, .control] {
            settings.holdModifier = modifier
            XCTAssertFalse(suppress("com.example.other"))
        }
    }
}
