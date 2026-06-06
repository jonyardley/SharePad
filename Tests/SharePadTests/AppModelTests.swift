import AVFoundation
@testable import SharePad
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    private func device(_ id: String) -> CaptureDevice {
        CaptureDevice(id: id, name: "Device \(id)")
    }

    private func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    private func makeModel(
        capture: FakeCaptureController,
        window: FakeShareWindow,
        preferences: Preferences
    ) -> AppModel {
        AppModel(
            preferences: preferences,
            capture: capture,
            window: window,
            thumbnailLayer: AVSampleBufferDisplayLayer(),
            sleep: { _ in } // retries run without real delay
        )
    }

    func testReconcileEmptyTearsDown() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: [])
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertGreaterThanOrEqual(window.hideCount, 1)
        XCTAssertFalse(model.isLive)
        XCTAssertNil(model.currentDeviceID)
        XCTAssertFalse(model.isConnected)
    }

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

    func testSecondDeviceDoesNotYankActive() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        await model.reconcile(devices: [device("a"), device("b")])
        XCTAssertEqual(capture.startedDeviceIDs, ["a"])
        XCTAssertEqual(model.currentDeviceID, "a")
        XCTAssertEqual(model.devices.count, 2)
    }

    func testRepicksWhenSelectedVanishes() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a"), device("b")])
        await model.reconcile(devices: [device("b")])
        XCTAssertEqual(capture.startedDeviceIDs, ["a", "b"])
        XCTAssertEqual(model.currentDeviceID, "b")
        XCTAssertTrue(model.isLive)
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

    func testSwitchToPersistsOnlyOnSuccess() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let prefs = try ephemeralPreferences()
        let model = makeModel(capture: capture, window: window, preferences: prefs)
        await model.reconcile(devices: [device("a"), device("b")])
        XCTAssertEqual(prefs.lastDeviceID, "a")
        capture.startResult = false
        await model.switchTo(deviceID: "b")
        XCTAssertEqual(prefs.lastDeviceID, "a")
        XCTAssertTrue(model.failed)
    }

    func testRestartResumesWhenPossible() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        capture.resumeResult = true
        await model.restart()
        XCTAssertTrue(model.isLive)
        XCTAssertEqual(capture.resumeCount, 1)
        // One confirm on the initial connect (#24), one on the resume path.
        XCTAssertEqual(capture.awaitFrameCount, 2)
        XCTAssertEqual(capture.startedDeviceIDs, ["a"]) // confirmed by a frame, no reconfigure
    }

    func testRestartFallsBackToStart() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        capture.resumeResult = false
        capture.startResult = true
        await model.restart()
        XCTAssertTrue(model.isLive)
        XCTAssertEqual(capture.resumeCount, 1)
        XCTAssertEqual(capture.startedDeviceIDs, ["a", "a"])
    }

    func testRestartFallsBackWhenResumeDeliversNoFrame() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        capture.resumeResult = true
        // Resume stalls (no frame), then the fallback start confirms one.
        capture.awaitFrameResults = [false, true]
        capture.startResult = true
        await model.restart()
        XCTAssertTrue(model.isLive)
        XCTAssertEqual(capture.resumeCount, 1)
        XCTAssertEqual(capture.startedDeviceIDs, ["a", "a"]) // fell back to a full start
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

    func testRestartFailsWhenResumeStallsAndStartFails() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        await model.reconcile(devices: [device("a")])
        capture.resumeResult = true
        capture.awaitFrameResult = false
        capture.startResult = false
        await model.restart()
        XCTAssertFalse(model.isLive)
        XCTAssertTrue(model.failed)
    }

    func testPopoverLifecycleTogglesThumbnail() throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        model.popoverDidAppear()
        XCTAssertEqual(capture.thumbnailActive, true)
        model.popoverDidDisappear()
        XCTAssertEqual(capture.thumbnailActive, false)
    }
}
