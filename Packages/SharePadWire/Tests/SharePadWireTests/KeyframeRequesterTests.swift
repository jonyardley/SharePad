@testable import SharePadWire
import XCTest

final class KeyframeRequesterTests: XCTestCase {
    func testConnectAsksAndWaitsForAKeyframe() {
        var requester = KeyframeRequester()
        XCTAssertEqual(requester.reduce(.connected(at: 0)), [.sendRequest])
        XCTAssertEqual(requester.reduce(.frameArrived(isKeyframe: false, at: 0.1)), [.discard])
        XCTAssertEqual(requester.reduce(.frameArrived(isKeyframe: true, at: 0.2)), [.decode])
        XCTAssertEqual(requester.reduce(.frameArrived(isKeyframe: false, at: 0.3)), [.decode])
    }

    func testDecodeErrorAndFlushBothAsk() {
        var requester = KeyframeRequester()
        XCTAssertEqual(requester.reduce(.decodeFailed(at: 5)), [.sendRequest])
        _ = requester.reduce(.frameArrived(isKeyframe: true, at: 5.1))
        XCTAssertEqual(requester.reduce(.layerFlushed(at: 6)), [.sendRequest])
    }

    func testRepeatedTriggersDoNotSpamRequests() {
        var requester = KeyframeRequester()
        _ = requester.reduce(.decodeFailed(at: 1))
        XCTAssertEqual(requester.reduce(.decodeFailed(at: 1.1)), [])
        XCTAssertEqual(requester.reduce(.frameArrived(isKeyframe: false, at: 1.5)), [.discard])
    }

    func testAsksAgainIfNoKeyframeArrivesWithinASecond() {
        var requester = KeyframeRequester()
        _ = requester.reduce(.decodeFailed(at: 1))
        XCTAssertEqual(
            requester.reduce(.frameArrived(isKeyframe: false, at: 2)),
            [.sendRequest, .discard]
        )
    }
}
