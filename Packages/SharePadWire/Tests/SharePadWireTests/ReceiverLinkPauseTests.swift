import Foundation
@testable import SharePadWire
import XCTest

final class ReceiverLinkPauseTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
    private let otherPad = Hello(deviceID: UUID(), deviceName: "Other iPad")

    func testPausingTheHostPausesTheLivePeer() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.hostPaused), [.sendPause(1)])
        XCTAssertTrue(link.isHostPaused)
    }

    func testResumingTheHostResumesTheLivePeer() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.hostPaused)
        XCTAssertEqual(link.reduce(.hostResumed), [.sendResume(1)])
        XCTAssertFalse(link.isHostPaused)
    }

    func testRepeatedPauseAndResumeSendNothing() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.hostResumed), [])
        _ = link.reduce(.hostPaused)
        XCTAssertEqual(link.reduce(.hostPaused), [])
    }

    func testPausingWithNoPeerIsRemembered() {
        var link = ReceiverLink()
        XCTAssertEqual(link.reduce(.hostPaused), [])
        XCTAssertEqual(link.reduce(.helloReceived(1, pad)), [.sendPause(1), .adopt(1)])
    }

    func testResumingWithNoPeerSendsNothing() {
        var link = ReceiverLink()
        _ = link.reduce(.hostPaused)
        XCTAssertEqual(link.reduce(.hostResumed), [])
        XCTAssertEqual(link.reduce(.helloReceived(1, pad)), [.adopt(1)])
    }

    func testAReconnectAdoptedWhilePausedIsPaused() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.hostPaused)
        _ = link.reduce(.closed(1, at: 10))
        XCTAssertEqual(link.reduce(.helloReceived(2, pad)), [.sendPause(2), .adopt(2)])
    }

    func testPausingDuringTheHoldPausesTheReconnect() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.closed(1, at: 10))
        XCTAssertEqual(link.reduce(.hostPaused), [])
        XCTAssertEqual(link.reduce(.helloReceived(2, pad)), [.sendPause(2), .adopt(2)])
    }

    func testAHalfOpenReplacementWhilePausedIsPaused() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.hostPaused)
        XCTAssertEqual(
            link.reduce(.helloReceived(2, pad)),
            [.close(1, .replaced), .sendPause(2), .adopt(2)]
        )
    }

    func testAStandbyPeerPromotedWhilePausedStaysPaused() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.helloReceived(2, otherPad))
        _ = link.reduce(.hostPaused)
        _ = link.reduce(.closed(1, at: 10))
        XCTAssertEqual(link.reduce(.holdElapsed(at: 15)), [.endShare, .adopt(2)])
        XCTAssertEqual(link.reduce(.hostResumed), [.sendResume(2)])
    }

    func testPausingDoesNotTouchStandbyPeers() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.helloReceived(2, otherPad))
        XCTAssertEqual(link.reduce(.hostPaused), [.sendPause(1)])
        XCTAssertEqual(link.reduce(.hostResumed), [.sendResume(1)])
    }
}
