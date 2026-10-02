@testable import SharePad
import XCTest

@MainActor
final class AppModelWirelessTests: AppModelTestCase {
    private let peer = WirelessPeer(id: UUID(), name: "Jon's iPad")

    private func makeWirelessModel(
        window: FakeShareWindow = FakeShareWindow(),
        wireless: FakeWirelessFeed = FakeWirelessFeed()
    ) throws -> AppModel {
        try makeModel(
            capture: FakeCaptureController(),
            window: window,
            preferences: ephemeralPreferences(),
            wireless: wireless
        )
    }

    func testFirstWirelessFrameHostsTheWirelessLayerAndShowsTheWindow() throws {
        let window = FakeShareWindow()
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(window: window, wireless: wireless)

        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertEqual(model.state, .live(.wireless))
        XCTAssertTrue(model.isSharing)
        XCTAssertTrue(model.isWindowVisible)
        XCTAssertTrue(window.feedLayers.last === wireless.hostedLayer)
        XCTAssertTrue(model.thumbnailLayer === wireless.thumbnailLayer)
    }

    func testReceiverSequenceAutoShowsOnTheFirstFrame() throws {
        let window = FakeShareWindow()
        let model = try makeWirelessModel(window: window)

        model.applyWireless(WirelessStatus(localNetwork: .granted))
        model.applyWireless(WirelessStatus(peer: peer, localNetwork: .granted))
        XCTAssertFalse(model.isWindowVisible)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true, localNetwork: .granted))

        XCTAssertTrue(model.isWindowVisible)
        XCTAssertEqual(window.shownSizes.count, 1)
    }

    func testAWindowTheUserHidStaysHiddenForTheRestOfTheLink() throws {
        let model = try makeWirelessModel()
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        model.toggleWindow()
        XCTAssertFalse(model.isWindowVisible)

        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true, isReconnecting: true))
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertFalse(model.isWindowVisible)
    }

    func testANewLinkAfterALostOneAutoShowsAgain() throws {
        let window = FakeShareWindow()
        let model = try makeWirelessModel(window: window)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        model.applyWireless(WirelessStatus())

        model.applyWireless(WirelessStatus(peer: peer))
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertTrue(model.isWindowVisible)
        XCTAssertEqual(window.shownSizes.count, 2)
    }

    func testConnectedPeerWithoutFramesWaitsWithTheWindowHidden() throws {
        let model = try makeWirelessModel()

        model.applyWireless(WirelessStatus(peer: peer))

        XCTAssertEqual(model.state, .starting(.wireless))
        XCTAssertTrue(model.isConnected)
        XCTAssertFalse(model.isWindowVisible)
    }

    func testLosingTheWirelessPeerWhileSharingRaisesShareLost() throws {
        let window = FakeShareWindow()
        let model = try makeWirelessModel(window: window)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        model.applyWireless(WirelessStatus())

        XCTAssertFalse(model.isWindowVisible)
        XCTAssertEqual(window.hideCount, 1)
        XCTAssertTrue(model.shareLostSignal)
        XCTAssertFalse(model.isConnected)
    }

    func testLosingTheLinkHidesAWindowStillOnScreenEvenIfTheFlagSaysHidden() throws {
        let window = FakeShareWindow()
        let model = try makeWirelessModel(window: window)
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        model.toggleWindow()
        window.isShowing = true

        model.applyWireless(WirelessStatus())

        XCTAssertFalse(window.isShowing)
        XCTAssertEqual(window.hideCount, 2)
        XCTAssertTrue(model.shareLostSignal)
    }

    func testReconnectingKeepsTheWindowUp() throws {
        let model = try makeWirelessModel()
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true, isReconnecting: true))

        XCTAssertTrue(model.isWindowVisible)
        XCTAssertEqual(model.state, .live(.wireless))
    }

    func testPopoverDrivesTheWirelessThumbnail() throws {
        let wireless = FakeWirelessFeed()
        let model = try makeWirelessModel(wireless: wireless)

        model.popoverDidAppear()
        XCTAssertEqual(wireless.thumbnailActive, true)
        model.popoverDidDisappear()
        XCTAssertEqual(wireless.thumbnailActive, false)
    }

    func testSourceLabelsNameTheLinkOnlyWhenWirelessIsThere() async throws {
        let model = try makeWirelessModel()
        await model.reconcile(devices: [device("a")])
        XCTAssertEqual(model.sourceOptions.map(\.label), ["Device a"])

        model.applyWireless(WirelessStatus(peer: peer))

        XCTAssertEqual(
            model.sourceOptions,
            [
                SourceOption(id: "a", label: "Device a · Cable"),
                SourceOption(id: AppModel.wirelessSourceID, label: "Jon's iPad · Wi-Fi"),
            ]
        )
    }

    func testUnpluggingACableDoesNotEndAWirelessShare() async throws {
        let model = try makeWirelessModel()
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))
        await model.reconcile(devices: [device("a")])

        await model.reconcile(devices: [])

        XCTAssertTrue(model.isWindowVisible)
        XCTAssertFalse(model.shareLostSignal)
        XCTAssertEqual(model.hostedFeed, .wireless)
    }

    func testExpiredTrialMetersAWirelessShare() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * 86400)
        let model = makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: prefs,
            wireless: FakeWirelessFeed()
        )

        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true))

        XCTAssertEqual(model.entitlement, .trialExpired)
        XCTAssertNotNil(model.sessionEndsAt)
    }

    func testUSBOnlyNeverSwapsTheWindowLayer() async throws {
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: window,
            preferences: ephemeralPreferences()
        )

        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: [])

        XCTAssertTrue(window.feedLayers.isEmpty)
    }
}
