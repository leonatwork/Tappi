import XCTest
@testable import Tappi

final class KeyboardLayoutCacheTests: XCTestCase {
    func testStartupBuildsUsableKeyboardLayoutMap() {
        // Exercise TIS/UCKeyTranslate through the real cache, independently of
        // the runner's selected layout or availability of Unicode layout data.
        let cache = KeyboardLayoutCache()
        let actions = (0..<128).compactMap { cache.keyMap[Int64($0)] }

        XCTAssertTrue(actions.contains(.closeWindow))
        XCTAssertTrue(actions.contains(.quitApp))
        XCTAssertEqual(cache.keyMap[51], .closeWindow)
        XCTAssertEqual(cache.keyMap[117], .closeWindow)
        let reservedKeys: [Int64] = [48, 50, 10, 53, 36, 49, 123, 124, 125, 126]
        for key in reservedKeys {
            XCTAssertNil(cache.keyMap[key])
        }
    }
}
