@testable import SharePad
import XCTest

final class WindowSizingTests: XCTestCase {
    func testPortraitScalesToLongSide() {
        let size = fittedContentSize(for: CGSize(width: 1668, height: 2388), maxLongSide: 900)
        XCTAssertEqual(size.height, 900, accuracy: 0.5)
        XCTAssertEqual(size.width, 1668.0 / 2388.0 * 900.0, accuracy: 0.5)
    }

    func testLandscapeScalesToLongSide() {
        let size = fittedContentSize(for: CGSize(width: 2388, height: 1668), maxLongSide: 900)
        XCTAssertEqual(size.width, 900, accuracy: 0.5)
        XCTAssertEqual(size.height, 1668.0 / 2388.0 * 900.0, accuracy: 0.5)
    }

    func testDoesNotUpscaleBelowMax() {
        let size = fittedContentSize(for: CGSize(width: 400, height: 300), maxLongSide: 900)
        XCTAssertEqual(size.width, 400, accuracy: 0.5)
        XCTAssertEqual(size.height, 300, accuracy: 0.5)
    }

    func testZeroGuardReturnsPositiveSize() {
        let size = fittedContentSize(for: .zero, maxLongSide: 900)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
