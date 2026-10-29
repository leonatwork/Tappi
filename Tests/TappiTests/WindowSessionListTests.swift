import XCTest
@testable import Tappi

final class WindowSessionListTests: XCTestCase {
    private struct Entry: SessionWindow {
        let id: String
        var pid: Int32 = 1
        var bundleID: String? = "com.example.Current"
        var isMinimized = false
        var isHidden = false
        var isOnActiveSpace = true
    }

    private let entries = [
        Entry(id: "current"),
        Entry(id: "otherApp", pid: 2, bundleID: "com.example.Other"),
        Entry(id: "minimized", isMinimized: true, isOnActiveSpace: false),
        Entry(id: "hidden", isHidden: true),
        Entry(id: "otherSpace", isOnActiveSpace: false),
        Entry(id: "hiddenMinimized", isMinimized: true, isHidden: true, isOnActiveSpace: false)
    ]

    private func ids(settings: Settings = Settings(), scope: SwitchScope = .allWindows,
                     frontPid: Int32? = 1) -> [String] {
        WindowSessionList.make(entries: entries, settings: settings, scope: scope,
                               frontPid: frontPid).map(\.id)
    }

    func testDefaultsIncludeAllWindowsInMRUOrder() {
        XCTAssertEqual(ids(), entries.map(\.id))
        XCTAssertEqual(ids(frontPid: nil), entries.map(\.id))
    }

    func testCurrentAppScopeUsesFrontmostPIDAndPreservesOrder() {
        XCTAssertEqual(ids(scope: .currentApp),
                       ["current", "minimized", "hidden", "otherSpace", "hiddenMinimized"])
        XCTAssertEqual(ids(scope: .currentApp, frontPid: 2), ["otherApp"])
        XCTAssertEqual(ids(scope: .currentApp, frontPid: nil), [])
    }

    func testMinimizedFilter() {
        var settings = Settings()
        settings.includeMinimized = false
        XCTAssertEqual(ids(settings: settings), ["current", "otherApp", "hidden", "otherSpace"])
    }

    func testExclusionRemovesEveryAppWindowInBothScopesCaseInsensitively() {
        var settings = Settings()
        settings.excludedApps = ["COM.EXAMPLE.CURRENT"]
        XCTAssertEqual(ids(settings: settings), ["otherApp"])
        XCTAssertEqual(ids(settings: settings, scope: .currentApp), [])
        XCTAssertEqual(ids(settings: settings, scope: .currentApp, frontPid: 2), ["otherApp"])
    }

    func testRemovingExclusionRestoresOriginalMRUOrderWithoutRebuildingEntries() {
        var settings = Settings()
        settings.excludedApps = ["com.example.other"]
        XCTAssertEqual(ids(settings: settings),
                       ["current", "minimized", "hidden", "otherSpace", "hiddenMinimized"])
        XCTAssertEqual(entries.map(\.id),
                       ["current", "otherApp", "minimized", "hidden", "otherSpace", "hiddenMinimized"])
        settings.excludedApps = []
        XCTAssertEqual(ids(settings: settings), entries.map(\.id))
    }

    func testUnknownBundleIDIsNotExcludedAndPassthroughDoesNotHideWindows() {
        var settings = Settings()
        settings.excludedApps = ["com.example.current"]
        settings.passthroughApps = ["com.example.other"]
        let unknown = Entry(id: "unknown", bundleID: nil)
        let result = WindowSessionList.make(entries: entries + [unknown], settings: settings,
                                            scope: .allWindows, frontPid: 1)
        XCTAssertEqual(result.map(\.id), ["otherApp", "unknown"])
    }

    func testLiveExclusionKeepsSelectedWindowIdentityAndUsesSuccessorWhenRemoved() {
        var settings = Settings()
        settings.excludedApps = ["com.example.current"]
        let removed = entries.indices.filter { entries[$0].bundleID == "com.example.Current" }
        let remaining = WindowSessionList.make(entries: entries, settings: settings,
                                               scope: .allWindows, frontPid: 1)
        let preserved = SessionSelection.afterRemoving(removed, selected: 1, remainingCount: remaining.count)
        XCTAssertEqual(preserved.map { remaining[$0].id }, "otherApp")
        let successor = SessionSelection.afterRemoving(removed, selected: 0, remainingCount: remaining.count)
        XCTAssertEqual(successor.map { remaining[$0].id }, "otherApp")
    }

    func testHiddenAppFilterAlsoExcludesHiddenMinimizedWindows() {
        var settings = Settings()
        settings.includeHiddenApps = false
        XCTAssertEqual(ids(settings: settings), ["current", "otherApp", "minimized", "otherSpace"])
    }

    func testOtherSpaceFilterDoesNotTreatMinimizedWindowsAsAnotherSpace() {
        var settings = Settings()
        settings.includeOtherSpaces = false
        XCTAssertEqual(ids(settings: settings),
                       ["current", "otherApp", "minimized", "hidden", "hiddenMinimized"])
    }

    func testFiltersComposeWithScopeAndDoNotMutateInput() {
        var settings = Settings()
        settings.includeMinimized = false
        settings.includeHiddenApps = false
        settings.includeOtherSpaces = false
        XCTAssertEqual(ids(settings: settings), ["current", "otherApp"])
        XCTAssertEqual(ids(settings: settings, scope: .currentApp), ["current"])
        XCTAssertEqual(entries.map(\.id),
                       ["current", "otherApp", "minimized", "hidden", "otherSpace", "hiddenMinimized"])
        XCTAssertTrue(WindowSessionList.make(entries: [Entry](), settings: settings,
                                             scope: .allWindows, frontPid: 1).isEmpty)
    }
}
