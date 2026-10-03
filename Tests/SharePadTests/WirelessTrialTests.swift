import AVFoundation
import CryptoKit
@testable import SharePad
import XCTest

@MainActor
final class WirelessTrialTests: GateTestCase {
    func testACableTakingOverAWirelessShareKeepsItsRemainingTime() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs, window: window, now: { clock }, sessionLimit: 100,
            wireless: FakeWirelessFeed(), permission: .authorized
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "iPad"),
            isReceiving: true
        ))
        let armed = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        XCTAssertEqual(armed.timeIntervalSinceReferenceDate, 1100, accuracy: 0.01)

        clock = Date(timeIntervalSinceReferenceDate: 1030) // 30s over Wi-Fi
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])

        XCTAssertEqual(model.hostedFeed, .usb)
        let carried = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        // 70s carried over → 1030+70=1100, NOT a fresh 1030+100=1130
        XCTAssertEqual(carried.timeIntervalSinceReferenceDate, 1100, accuracy: 0.01)
    }

    func testUnpluggingTheCableHandsItsRemainingTimeBackToWireless() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs, window: window, now: { clock }, sessionLimit: 100,
            wireless: FakeWirelessFeed(), permission: .authorized
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "iPad"),
            isReceiving: true
        ))
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])

        clock = Date(timeIntervalSinceReferenceDate: 1050)
        await model.reconcile(devices: [])

        XCTAssertEqual(model.hostedFeed, .wireless)
        XCTAssertTrue(model.isWindowVisible)
        let handedBack = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        XCTAssertEqual(handedBack.timeIntervalSinceReferenceDate, 1100, accuracy: 0.01)
    }

    func testAPausedWirelessShareStaysPausedWhenTheCableTakesOver() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let model = makeModel(
            preferences: prefs, sleep: { _ in }, sessionLimit: 100,
            wireless: FakeWirelessFeed(), permission: .authorized
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "iPad"),
            isReceiving: true
        ))
        await poll { model.isTrialOverlayShown }

        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])

        XCTAssertEqual(model.hostedFeed, .usb)
        XCTAssertTrue(model.isTrialOverlayShown)
        XCTAssertNil(model.sessionEndsAt)
    }

    func testTheTrialOverlayPausesAWirelessShare() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let wireless = FakeWirelessFeed()
        let model = makeModel(
            preferences: prefs, sleep: { _ in }, sessionLimit: 100,
            wireless: wireless, permission: .authorized
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "iPad"),
            isReceiving: true
        ))
        XCTAssertEqual(wireless.hostActive.last, true)

        await poll { model.isTrialOverlayShown }

        XCTAssertEqual(model.hostedFeed, .wireless)
        XCTAssertEqual(wireless.hostActive.last, false)
    }

    func testHidingAPausedWirelessShareResumesTheIPad() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let wireless = FakeWirelessFeed()
        let model = makeModel(
            preferences: prefs, sleep: { _ in }, sessionLimit: 100,
            wireless: wireless, permission: .authorized
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "iPad"),
            isReceiving: true
        ))
        await poll { model.isTrialOverlayShown }

        model.toggleWindow()

        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(wireless.hostActive.last, true)
    }
}
