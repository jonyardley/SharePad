@testable import SharePad
import XCTest

@MainActor
final class AppModelShareLostTests: AppModelTestCase {
    func testTeardownWhileSharingRaisesShareLost() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")]) // auto-shows → window visible
        XCTAssertTrue(model.isWindowVisible)
        await model.reconcile(devices: [])
        XCTAssertTrue(model.shareLostSignal) // synchronous: auto-expire hasn't run yet
    }

    func testTeardownWhileHiddenIsSilent() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let prefs = try ephemeralPreferences()
        prefs.autoShowOnConnect = false
        let model = makeModel(capture: capture, window: window, preferences: prefs)
        await model.reconcile(devices: [device("a")]) // live, but window stays hidden
        XCTAssertFalse(model.isWindowVisible)
        await model.reconcile(devices: [])
        XCTAssertFalse(model.shareLostSignal)
    }

    func testReconnectClearsShareLost() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: [])
        XCTAssertTrue(model.shareLostSignal)
        await model.reconcile(devices: [device("a")]) // replug → reconnect supersedes
        XCTAssertFalse(model.shareLostSignal)
        XCTAssertTrue(model.isLive)
    }

    func testDismissShareLostClears() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: [])
        XCTAssertTrue(model.shareLostSignal)
        model.dismissShareLost()
        XCTAssertFalse(model.shareLostSignal)
        XCTAssertNil(model.shareLostDismissTask)
    }

    func testShareLostAutoExpires() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: []) // expire task runs with the no-op test sleep
        await model.shareLostDismissTask?.value
        XCTAssertFalse(model.shareLostSignal)
    }
}
