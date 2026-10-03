@testable import SharePad
import XCTest

@MainActor
final class AppModelWirelessHostTests: AppModelTestCase {
    private let peer = WirelessPeer(id: UUID(), name: "Jon's iPad")

    private func makeWirelessModel(wireless: FakeWirelessFeed) throws -> AppModel {
        try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: wireless,
            permission: .authorized
        )
    }

    func testAWirelessShareKeepsWirelessActive() throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)

        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertEqual(wireless.hostActive.last, true)
        XCTAssertFalse(wireless.hostActive.contains(false))
    }

    func testACableGoingLiveOverAWirelessSharePausesWireless() async throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        await model.reconcile(devices: [device("a")])

        XCTAssertEqual(model.hostedFeed, .usb)
        XCTAssertEqual(wireless.hostActive.last, false)
    }

    func testUnpluggingTheCableResumesWireless() async throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        await model.reconcile(devices: [device("a")])
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: false))

        await model.reconcile(devices: [])

        XCTAssertEqual(model.hostedFeed, .wireless)
        XCTAssertEqual(wireless.hostActive.last, true)
    }

    func testAPausedWirelessFeedDoesNotTakeTheWindowFromARestartingCable() async throws {
        let wireless = FakeWirelessFeed()
        let capture = FakeCaptureController()
        let model = try makeModel(
            capture: capture,
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: wireless,
            permission: .authorized
        )
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        await model.reconcile(devices: [device("a")])
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: false))
        capture.holdsResume = true

        let restarting = Task { await model.restart() }
        for _ in 0 ..< 100_000 where !capture.isResumeHeld {
            await Task.yield()
        }
        XCTAssertTrue(capture.isResumeHeld)
        XCTAssertFalse(model.isLive)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: false))

        XCTAssertEqual(model.hostedFeed, .usb)
        XCTAssertEqual(wireless.hostActive.last, false)

        capture.releaseResume()
        await restarting.value
        XCTAssertEqual(model.hostedFeed, .usb)
        XCTAssertEqual(wireless.hostActive.last, false)
    }

    func testACableWithNoWirelessPeerStillPausesTheNextOne() async throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)

        await model.reconcile(devices: [device("a")])

        XCTAssertEqual(wireless.hostActive.last, false)
    }

    func testRepeatsAreNotSent() throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertEqual(wireless.hostActive, [true])
    }
}
