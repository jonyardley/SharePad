@testable import SharePad
import XCTest

final class FrameThrottleTests: XCTestCase {
    private let interval = 1.0 / 15.0

    func testRendersFirstFrameWhenNoPrior() {
        XCTAssertTrue(shouldRenderFrame(
            currentSeconds: 5,
            lastRenderedSeconds: nil,
            minInterval: interval
        ))
    }

    func testRendersWhenElapsedExceedsInterval() {
        XCTAssertTrue(shouldRenderFrame(
            currentSeconds: 2,
            lastRenderedSeconds: 1,
            minInterval: interval
        ))
    }

    func testSkipsWhenElapsedBelowInterval() {
        XCTAssertFalse(shouldRenderFrame(
            currentSeconds: 1.0,
            lastRenderedSeconds: 0.95,
            minInterval: interval
        ))
    }

    func testRendersAtExactlyInterval() {
        XCTAssertTrue(shouldRenderFrame(
            currentSeconds: 1.0,
            lastRenderedSeconds: 0.5,
            minInterval: 0.5
        ))
    }

    func testRendersOnBackwardsTimestamp() {
        XCTAssertTrue(shouldRenderFrame(
            currentSeconds: 0.1,
            lastRenderedSeconds: 5.0,
            minInterval: interval
        ))
    }
}
