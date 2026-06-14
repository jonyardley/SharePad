@testable import SharePad
import XCTest

final class SessionCountdownTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 0)

    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(
            SessionCountdown.remainingText(until: base.addingTimeInterval(272), now: base),
            "4:32"
        )
        XCTAssertEqual(
            SessionCountdown.remainingText(until: base.addingTimeInterval(300), now: base),
            "5:00"
        )
        XCTAssertEqual(
            SessionCountdown.remainingText(until: base.addingTimeInterval(9), now: base),
            "0:09"
        )
    }

    func testCeilsPartialSecond() {
        XCTAssertEqual(
            SessionCountdown.remainingText(until: base.addingTimeInterval(0.4), now: base),
            "0:01"
        )
    }

    func testClampsToZeroPastDeadline() {
        XCTAssertEqual(
            SessionCountdown.remainingText(until: base.addingTimeInterval(-5), now: base),
            "0:00"
        )
    }
}
