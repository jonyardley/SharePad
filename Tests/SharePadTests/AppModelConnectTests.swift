@testable import SharePad
import XCTest

@MainActor
final class AppModelConnectTests: AppModelTestCase {
    func testFirstDeviceStartsAndAutoShows() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let prefs = try ephemeralPreferences()
        let model = makeModel(capture: capture, window: window, preferences: prefs)
        await model.reconcile(devices: [device("a")])
        XCTAssertEqual(capture.startedDeviceIDs, ["a"])
        XCTAssertTrue(model.isLive)
        XCTAssertEqual(window.shownSizes.count, 1)
        XCTAssertEqual(prefs.lastDeviceID, "a")
    }

    func testAutoShowOffDoesNotPresentWindow() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let prefs = try ephemeralPreferences()
        prefs.autoShowOnConnect = false
        let model = makeModel(capture: capture, window: window, preferences: prefs)
        await model.reconcile(devices: [device("a")])
        XCTAssertTrue(model.isLive)
        XCTAssertTrue(window.shownSizes.isEmpty)
    }

    func testStartFailureSurfacesFailed() async throws {
        let capture = FakeCaptureController()
        capture.startResult = false
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.retryTask?.value // exhaust the bounded retry window
        XCTAssertFalse(model.isLive)
        XCTAssertTrue(model.failed)
        XCTAssertEqual(capture.startedDeviceIDs.count,
                       AppModel.firstConnectAttempts) // no infinite loop
    }

    func testStartConfirmStallSurfacesFailed() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        capture.startResult = true
        capture.awaitFrameResult = false // session runs but no frame ever arrives
        await model.reconcile(devices: [device("a")])
        await model.retryTask?.value // exhaust the bounded retry window
        XCTAssertFalse(model.isLive)
        XCTAssertTrue(model.failed)
        XCTAssertEqual(
            capture.startedDeviceIDs,
            Array(repeating: "a", count: AppModel.firstConnectAttempts)
        )
    }

    func testFirstConnectRecoversAfterStall() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let prefs = try ephemeralPreferences()
        let model = makeModel(capture: capture, window: window, preferences: prefs)
        // Attempt 1 stalls (no frame), attempt 2 confirms — the settling-window repro.
        capture.awaitFrameResults = [false, true]
        await model.reconcile(devices: [device("a")])
        await model.retryTask?.value
        XCTAssertTrue(model.isLive)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(capture.startedDeviceIDs, ["a", "a"])
        XCTAssertEqual(window.shownSizes.count, 1) // auto-shown once, not per attempt
        XCTAssertEqual(prefs.lastDeviceID, "a")
    }

    func testFirstConnectExhaustsIntoFailed() async throws {
        let capture = FakeCaptureController()
        capture.awaitFrameResult = false // every confirm stalls
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.retryTask?.value
        XCTAssertFalse(model.isLive)
        XCTAssertTrue(model.failed)
        XCTAssertEqual(capture.startedDeviceIDs.count, AppModel.firstConnectAttempts)
        XCTAssertGreaterThanOrEqual(window.hideCount, 1)
    }

    func testTeardownDuringRetryStops() async throws {
        let capture = FakeCaptureController()
        capture.awaitFrameResult = false // first connect stalls → spawns the retry task
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        let retry = model.retryTask // teardown nils the handle; keep it to await completion
        XCTAssertNotNil(retry) // a stalled first attempt must have spawned the retry
        await model.reconcile(devices: []) // device vanishes mid-window
        await retry?.value // superseded → bails without re-failing
        XCTAssertNil(model.currentDeviceID)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(capture.stopCount, 1)
    }
}
