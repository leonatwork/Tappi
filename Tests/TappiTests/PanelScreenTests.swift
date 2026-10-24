import AppKit
import XCTest
@testable import Tappi

final class PanelScreenTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let left = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
    private let above = CGRect(x: 0, y: 900, width: 1440, height: 900)

    private func choose(_ mode: PanelScreen, window: CGRect? = nil,
                        mouse: CGPoint = CGPoint(x: 100, y: 100), main: Int? = 0) -> Int? {
        PanelScreenSelection.choose(mode: mode, frames: [primary, left, above],
                                    primaryTop: primary.maxY, windowFrame: window,
                                    mousePosition: mouse, mainIndex: main)
    }

    func testActiveWindowOnNegativeCoordinateScreen() {
        let window = CGRect(x: -1800, y: 200, width: 800, height: 600)
        XCTAssertEqual(choose(.active, window: window), 1)
    }

    func testQuartzWindowCoordinatesFlipAboutPrimaryScreenNotDesktopUnion() {
        let window = CGRect(x: 200, y: -800, width: 800, height: 600)
        XCTAssertEqual(PanelScreenSelection.appKitFrame(window, primaryTop: 900),
                       CGRect(x: 200, y: 1100, width: 800, height: 600))
        XCTAssertEqual(choose(.active, window: window), 2)
    }

    func testSpanningWindowUsesLargestIntersection() {
        XCTAssertEqual(choose(.active, window: CGRect(x: -700, y: 100, width: 800, height: 500)), 1)
    }

    func testMouseCoordinatesAreAlreadyAppKitIncludingNegativeY() {
        XCTAssertEqual(choose(.mouse, mouse: CGPoint(x: -100, y: -100)), 1)
        XCTAssertEqual(choose(.mouse, mouse: CGPoint(x: 100, y: 1200)), 2)
    }

    func testMainIgnoresWindowAndMouse() {
        XCTAssertEqual(choose(.main, window: CGRect(x: -1800, y: 200, width: 800, height: 600),
                              mouse: CGPoint(x: -100, y: -100)), 0)
        XCTAssertEqual(choose(.main, main: 2), 2)
    }

    func testMissingOrOffscreenFocusFallsBackToMouseThenMainThenFirst() {
        XCTAssertEqual(choose(.active, mouse: CGPoint(x: -100, y: -100)), 1)
        XCTAssertEqual(choose(.active, window: .zero, mouse: CGPoint(x: -100, y: -100)), 1)
        XCTAssertEqual(choose(.active, window: CGRect(x: 5000, y: 0, width: 100, height: 100),
                              mouse: CGPoint(x: 5000, y: 5000), main: 2), 2)
        XCTAssertEqual(choose(.mouse, mouse: CGPoint(x: 5000, y: 5000), main: nil), 0)
        XCTAssertEqual(choose(.main, main: 99), 0)
    }

    func testNoScreensReturnsNilForEveryMode() {
        for mode in PanelScreen.allCases {
            XCTAssertNil(PanelScreenSelection.choose(mode: mode, frames: [], primaryTop: 0,
                                                    windowFrame: nil, mousePosition: .zero, mainIndex: 0))
        }
    }
}
