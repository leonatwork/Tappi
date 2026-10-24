import AppKit
import XCTest
@testable import Tappi

final class TileLayoutTests: XCTestCase {
    private let screen = CGRect(x: -1600, y: 23, width: 1600, height: 877)

    private func layout(_ count: Int, width: Double = 148, columns: Int = 7,
                        frame: CGRect? = nil) -> TileLayout {
        TileLayout.compute(count: count, tileWidth: width, maxColumns: columns,
                           visibleFrame: frame ?? screen)
    }

    private func assertFits(_ layout: TileLayout, in frame: CGRect,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(layout.panelSize.width, frame.width, file: file, line: line)
        XCTAssertLessThanOrEqual(layout.panelSize.height, frame.height, file: file, line: line)
        let bounds = CGRect(origin: .zero, size: layout.panelSize)
        for (index, tile) in layout.tiles.enumerated() {
            XCTAssertTrue(bounds.contains(tile), file: file, line: line)
            XCTAssertEqual(layout.tiles.firstIndex { $0.contains(CGPoint(x: tile.midX, y: tile.midY)) },
                           index, file: file, line: line)
        }
    }

    func testFewWindowsKeepOriginalGeometry() {
        let result = layout(3)
        XCTAssertEqual(result.columns, 3)
        XCTAssertEqual(result.tileSize.width, 148)
        XCTAssertEqual(result.tileSize.height, 130.8, accuracy: 0.0001)
        XCTAssertEqual(result.panelSize.width, 488)
        XCTAssertEqual(result.panelSize.height, 158.8, accuracy: 0.0001)
        assertFits(result, in: screen)
    }

    func testOriginalWrappingIsUnchangedWhenItFits() {
        let result = layout(10)
        XCTAssertEqual(result.columns, 7)
        XCTAssertEqual(result.tileSize.width, 148)
        XCTAssertEqual(result.tiles.count, 10)
        XCTAssertGreaterThan(result.tiles[0].minY, result.tiles[7].minY)
        assertFits(result, in: screen)
    }

    func testClosingWindowRemovesUnusedColumn() {
        var result = layout(3)
        result.reduceCount(to: 2, tileWidth: 148, maxColumns: 7, visibleFrame: screen)

        XCTAssertEqual(result.tiles.count, 2)
        XCTAssertEqual(result.columns, 2)
        XCTAssertEqual(result.panelSize.width, 332)
        XCTAssertEqual(result.panelSize.height, 158.8, accuracy: 0.0001)
        XCTAssertEqual(result.tileSize.width, 148)
        assertFits(result, in: screen)
    }

    func testQuittingAppRemovesEmptyRows() {
        var result = layout(15)
        result.reduceCount(to: 7, tileWidth: 148, maxColumns: 7, visibleFrame: screen)

        XCTAssertEqual(result.tiles.count, 7)
        XCTAssertEqual(result.columns, 7)
        XCTAssertEqual(result.panelSize.height, 158.8, accuracy: 0.0001)
        XCTAssertEqual(result.tiles[0].minY, TileLayout.outerPadding, accuracy: 0.0001)
        assertFits(result, in: screen)
    }

    func testRemovingWindowsRestoresOriginalTileSizeWhenItFits() {
        var result = layout(20, width: 320, columns: 4)
        XCTAssertLessThan(result.tileSize.width, 320)

        result.reduceCount(to: 4, tileWidth: 320, maxColumns: 4, visibleFrame: screen)

        XCTAssertEqual(result.tiles.count, 4)
        XCTAssertEqual(result.tileSize, CGSize(width: 320, height: 234))
        XCTAssertEqual(result.panelSize, CGSize(width: 1332, height: 262))
        assertFits(result, in: screen)
    }

    func testTruncatedLayoutStaysUnchangedUntilWindowsAreRemoved() {
        var result = layout(200, width: 320, columns: 4)
        let prepared = result
        result.reduceCount(to: prepared.tiles.count, tileWidth: 320,
                           maxColumns: 4, visibleFrame: screen)

        XCTAssertEqual(result.tiles, prepared.tiles)
        XCTAssertEqual(result.columns, prepared.columns)
        XCTAssertEqual(result.panelSize, prepared.panelSize)
        XCTAssertEqual(result.tileSize, prepared.tileSize)

        result.reduceCount(to: 4, tileWidth: 320, maxColumns: 4, visibleFrame: screen)
        XCTAssertEqual(result.tiles.count, 4, "Removed or truncated windows must not return")
        XCTAssertEqual(result.tileSize.width, 320)
        assertFits(result, in: screen)
    }

    func testOverflowShrinksAllTilesWithOriginalAspectRatio() {
        let result = layout(20, width: 320, columns: 4)
        XCTAssertEqual(result.columns, 4)
        XCTAssertEqual(result.tiles.count, 20)
        XCTAssertLessThan(result.tileSize.width, 320)
        XCTAssertGreaterThanOrEqual(result.tileSize.width, 96)
        XCTAssertEqual(result.tileSize.height / result.tileSize.width, 234.0 / 320.0, accuracy: 0.0001)
        assertFits(result, in: screen)
    }

    func testMinimumWidthTruncatesToWholeVisibleTiles() {
        let result = layout(200, width: 320, columns: 4)
        XCTAssertEqual(result.tileSize.width, 96)
        XCTAssertLessThan(result.tiles.count, 200)
        XCTAssertEqual(result.tiles.count % result.columns, 0)
        let nextRowHeight = result.panelSize.height + result.tileSize.height + TileLayout.gap
        XCTAssertGreaterThan(nextRowHeight, screen.height)
        assertFits(result, in: screen)
    }

    func testNarrowScreenShrinksWithoutGoingBelowMinimum() {
        let frame = CGRect(x: -200, y: -400, width: 180, height: 800)
        let result = layout(3, width: 320, columns: 4, frame: frame)
        XCTAssertEqual(result.columns, 1)
        XCTAssertEqual(result.tiles.count, 3)
        XCTAssertGreaterThanOrEqual(result.tileSize.width, 96)
        XCTAssertLessThan(result.tileSize.width, 320)
        assertFits(result, in: frame)
    }

    func testNoWindowsOrNoRoomProducesEmptyLayout() {
        for result in [layout(0), layout(-1), layout(3, frame: .zero),
                       layout(3, frame: CGRect(x: 0, y: 0, width: 100, height: 100))] {
            XCTAssertTrue(result.tiles.isEmpty)
            XCTAssertEqual(result.panelSize, .zero)
        }
    }

    func testVeryNarrowScreenUsesFullVisibleWidthForMinimumTile() {
        let frame = CGRect(x: -124, y: 0, width: 124, height: 100)
        let result = layout(20, width: 320, columns: 4, frame: frame)
        XCTAssertEqual(result.tileSize.width, 96)
        XCTAssertEqual(result.tiles.count, 1)
        assertFits(result, in: frame)
    }

    func testScreenTooShortForMinimumTileProducesEmptyLayout() {
        let result = layout(20, frame: CGRect(x: 0, y: 0, width: 1600, height: 60))
        XCTAssertTrue(result.tiles.isEmpty)
        XCTAssertEqual(result.panelSize, .zero)
    }
}
