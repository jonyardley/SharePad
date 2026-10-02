import Foundation
@testable import SharePadWire
import XCTest

final class SenderLinkTests: XCTestCase {
    private let mac = Hello(deviceID: UUID(), deviceName: "Mac")

    private func live(_ link: inout SenderLink, peer: String = "Studio") {
        _ = link.reduce(.start)
        _ = link.reduce(.found([peer]))
        _ = link.reduce(.connectionReady)
        _ = link.reduce(.helloReceived(mac))
    }

    func testHappyPathToLive() {
        var link = SenderLink()
        XCTAssertEqual(link.reduce(.start), [.startBrowsing])
        XCTAssertEqual(link.reduce(.found([])), [])
        XCTAssertEqual(
            link.reduce(.found(["Studio"])),
            [.connect("Studio"), .scheduleConnectTimeout(attempt: 1, after: 5)]
        )
        XCTAssertEqual(link.reduce(.connectionReady), [.stopBrowsing, .sendHello])
        XCTAssertEqual(link.reduce(.helloReceived(mac)), [.startStreaming])
        XCTAssertEqual(link.phase, .live("Studio"))
        XCTAssertEqual(link.lastPeer, "Studio")
    }

    func testPrefersTheMacUsedLast() {
        var link = SenderLink(lastPeer: "Office")
        _ = link.reduce(.start)
        XCTAssertEqual(link.reduce(.found(["Home", "Office"])).first, .connect("Office"))
    }

    func testIncompatibleVersionClosesAndStops() {
        var link = SenderLink()
        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionReady)
        let future = Hello(protocolVersion: 99, deviceID: UUID(), deviceName: "Mac")
        XCTAssertEqual(link.reduce(.helloReceived(future)), [.closeConnection])
        XCTAssertEqual(link.phase, .incompatible("Studio", peerVersion: 99))
        XCTAssertEqual(link.reduce(.connectionLost), [])
    }

    func testPauseAndResume() {
        var link = SenderLink()
        live(&link)
        XCTAssertEqual(link.reduce(.pauseReceived), [.pauseStreaming])
        XCTAssertEqual(link.phase, .paused("Studio"))
        XCTAssertEqual(link.reduce(.pauseReceived), [])
        XCTAssertEqual(link.reduce(.resumeReceived), [.resumeStreaming])
        XCTAssertEqual(link.phase, .live("Studio"))
    }

    func testLosingALiveLinkBacksOffThenSearches() {
        var link = SenderLink()
        live(&link)
        XCTAssertEqual(
            link.reduce(.connectionLost),
            [.stopStreaming, .stopBrowsing, .scheduleRetry(after: 0.5)]
        )
        XCTAssertEqual(link.phase, .backingOff)
        XCTAssertEqual(link.reduce(.retryElapsed), [.startBrowsing])
        XCTAssertEqual(link.phase, .searching)
    }

    func testLosingAConnectionWhileConnectingBacksOff() {
        var link = SenderLink()
        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        XCTAssertEqual(link.reduce(.connectionLost), [.stopBrowsing, .scheduleRetry(after: 0.5)])
        XCTAssertEqual(link.phase, .backingOff)
    }

    func testLosingAConnectionWhileHandshakingBacksOff() {
        var link = SenderLink()
        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionReady)
        XCTAssertEqual(link.reduce(.connectionLost), [.stopBrowsing, .scheduleRetry(after: 0.5)])
        XCTAssertEqual(link.phase, .backingOff)
    }

    func testBackoffDoublesToACapAndResetsOnceLive() {
        var link = SenderLink()
        _ = link.reduce(.start)
        var delays: [TimeInterval] = []
        for _ in 0 ..< 6 {
            _ = link.reduce(.found(["Studio"]))
            if case let .scheduleRetry(delay) = link.reduce(.connectionLost).last {
                delays.append(delay)
            }
            _ = link.reduce(.retryElapsed)
        }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 5, 5])
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionReady)
        _ = link.reduce(.helloReceived(mac))
        XCTAssertEqual(link.reduce(.connectionLost).last, .scheduleRetry(after: 0.5))
    }

    func testRetryElapsedOutsideBackoffIsIgnored() {
        var link = SenderLink()
        XCTAssertEqual(link.reduce(.retryElapsed), [])
        live(&link)
        XCTAssertEqual(link.reduce(.retryElapsed), [])
        XCTAssertEqual(link.phase, .live("Studio"))
    }

    func testOnlyTheCurrentConnectTimeoutCounts() {
        var link = SenderLink()
        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionLost)
        _ = link.reduce(.retryElapsed)
        XCTAssertEqual(
            link.reduce(.found(["Studio"])).last,
            .scheduleConnectTimeout(attempt: 2, after: 5)
        )
        _ = link.reduce(.connectionReady)
        XCTAssertEqual(link.reduce(.connectTimedOut(attempt: 1)), [])
        XCTAssertEqual(link.phase, .handshaking("Studio"))
        XCTAssertEqual(
            link.reduce(.connectTimedOut(attempt: 2)),
            [.closeConnection, .stopBrowsing, .scheduleRetry(after: 1)]
        )
        XCTAssertEqual(link.phase, .backingOff)
    }

    func testConnectTimeoutAfterGoingLiveIsIgnored() {
        var link = SenderLink()
        live(&link)
        XCTAssertEqual(link.reduce(.connectTimedOut(attempt: 1)), [])
        XCTAssertEqual(link.phase, .live("Studio"))
    }

    func testStopFromIncompatibleAndFromBackoffGoesIdle() {
        var link = SenderLink()
        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionReady)
        _ = link.reduce(.helloReceived(Hello(
            protocolVersion: 99,
            deviceID: UUID(),
            deviceName: "Mac"
        )))
        XCTAssertEqual(link.reduce(.stop), [.stopStreaming, .closeConnection, .stopBrowsing])
        XCTAssertEqual(link.phase, .idle)

        _ = link.reduce(.start)
        _ = link.reduce(.found(["Studio"]))
        _ = link.reduce(.connectionLost)
        XCTAssertEqual(link.reduce(.stop), [.stopStreaming, .closeConnection, .stopBrowsing])
        XCTAssertEqual(link.phase, .idle)
        XCTAssertEqual(link.reduce(.retryElapsed), [])
    }

    func testStopTearsEverythingDown() {
        var link = SenderLink()
        live(&link)
        XCTAssertEqual(link.reduce(.stop), [.stopStreaming, .closeConnection, .stopBrowsing])
        XCTAssertEqual(link.phase, .idle)
        XCTAssertEqual(link.reduce(.stop), [])
    }
}

final class ReceiverLinkTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
    private let otherPad = Hello(deviceID: UUID(), deviceName: "Other iPad")

    func testFirstPeerGoesLive() {
        var link = ReceiverLink()
        XCTAssertEqual(link.reduce(.opened(1)), [.sendHello(1)])
        XCTAssertEqual(link.reduce(.helloReceived(1, pad)), [.adopt(1)])
        XCTAssertEqual(link.phase, .live(.init(connection: 1, hello: pad)))
    }

    func testIncompatibleVersionIsClosed() {
        var link = ReceiverLink()
        let old = Hello(protocolVersion: 0, deviceID: UUID(), deviceName: "Old")
        XCTAssertEqual(
            link.reduce(.helloReceived(1, old)),
            [.close(1, .incompatible(peerVersion: 0))]
        )
        XCTAssertEqual(link.phase, .waiting)
    }

    func testOnlyOneStreamAtATime() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.helloReceived(2, otherPad)), [.sendPause(2)])
        XCTAssertEqual(link.standby.map(\.connection), [2])
    }

    func testSameIPadReconnectingReplacesAHalfOpenConnection() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.helloReceived(2, pad)), [.close(1, .replaced), .adopt(2)])
        XCTAssertEqual(link.reduce(.closed(1, at: 3)), [])
        XCTAssertEqual(link.phase, .live(.init(connection: 2, hello: pad)))
    }

    func testShortDropIsHeldAndRecovers() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.closed(1, at: 10)), [.scheduleHoldCheck(after: 5)])
        XCTAssertEqual(link.reduce(.helloReceived(2, pad)), [.adopt(2)])
        XCTAssertEqual(link.reduce(.holdElapsed(at: 15)), [])
        XCTAssertEqual(link.phase, .live(.init(connection: 2, hello: pad)))
    }

    func testHoldExpiresAfterFiveSeconds() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.closed(1, at: 10))
        XCTAssertEqual(link.reduce(.holdElapsed(at: 14.9)), [])
        XCTAssertEqual(link.reduce(.holdElapsed(at: 15)), [.endShare])
        XCTAssertEqual(link.phase, .waiting)
    }

    func testAnotherIPadWaitsOutTheHoldThenTakesOver() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.closed(1, at: 10))
        XCTAssertEqual(link.reduce(.helloReceived(2, otherPad)), [.sendPause(2)])
        XCTAssertEqual(
            link.reduce(.holdElapsed(at: 15)),
            [.endShare, .sendResume(2), .adopt(2)]
        )
        XCTAssertEqual(link.phase, .live(.init(connection: 2, hello: otherPad)))
        XCTAssertTrue(link.standby.isEmpty)
    }

    func testAStandbyPeerLeavingIsForgotten() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.helloReceived(2, otherPad))
        _ = link.reduce(.closed(2, at: 4))
        XCTAssertTrue(link.standby.isEmpty)
    }

    func testARepeatedHelloOnTheLiveConnectionChangesNothing() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        XCTAssertEqual(link.reduce(.helloReceived(1, pad)), [])
        XCTAssertEqual(link.phase, .live(.init(connection: 1, hello: pad)))
    }

    func testAStandbyIPadReconnectingReplacesItsOldEntry() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.helloReceived(2, otherPad))
        XCTAssertEqual(
            link.reduce(.helloReceived(3, otherPad)),
            [.close(2, .replaced), .sendPause(3)]
        )
        XCTAssertEqual(link.standby.map(\.connection), [3])
    }

    func testAStaleHoldCheckAfterARehold() {
        var link = ReceiverLink()
        _ = link.reduce(.helloReceived(1, pad))
        _ = link.reduce(.closed(1, at: 10))
        _ = link.reduce(.helloReceived(2, pad))
        _ = link.reduce(.closed(2, at: 12))
        XCTAssertEqual(link.reduce(.holdElapsed(at: 15)), [])
        XCTAssertEqual(link.phase, .holding(.init(connection: 2, hello: pad), since: 12))
        XCTAssertEqual(link.reduce(.holdElapsed(at: 17)), [.endShare])
        XCTAssertEqual(link.phase, .waiting)
    }
}
