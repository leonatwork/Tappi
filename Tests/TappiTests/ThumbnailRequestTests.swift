import AppKit
import XCTest
@testable import Tappi

final class ThumbnailRequestTests: XCTestCase {
    func testCaptureUsesExactlySelectedScreensBackingScale() {
        let size = CGSize(width: 132, height: 84)
        let standard = ThumbnailRequest(size: size, scale: 1)
        XCTAssertEqual(standard.pixelWidth, 132)
        XCTAssertEqual(standard.pixelHeight, 84)
        XCTAssertEqual(standard.scale, 1)
        let retina = ThumbnailRequest(size: size, scale: 2)
        XCTAssertEqual(retina.pixelWidth, 264)
        XCTAssertEqual(retina.pixelHeight, 168)
        XCTAssertEqual(retina.scale, 2)
    }

    func testCacheIdentityIncludesScaleAndPreviewSize() {
        let request = ThumbnailRequest(size: CGSize(width: 132, height: 84), scale: 1)
        XCTAssertNotEqual(request, ThumbnailRequest(size: CGSize(width: 132, height: 84), scale: 2))
        XCTAssertNotEqual(request, ThumbnailRequest(size: CGSize(width: 200, height: 120), scale: 1))
    }
}
