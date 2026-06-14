@testable import SharePad
import XCTest

@MainActor
final class AppModelLifecycleTests: AppModelTestCase {
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

    func testCaptureRestartEventTriggersRestart() async throws {
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = try makeModel(
            capture: capture,
            window: window,
            preferences: ephemeralPreferences()
        )
        // Establish a selected device so restart() does observable work.
        await model.reconcile(devices: [device("a")])
        let resumesBefore = capture.resumeCount

        let observation = Task { await model.observeRestarts() }
        defer { observation.cancel() }
        capture.sendRestart()

        // Let the observer process the event (cooperative yield; both run on MainActor).
        var processed = false
        for _ in 0 ..< 1000 {
            if capture.resumeCount > resumesBefore { processed = true; break }
            await Task.yield()
        }
        XCTAssertTrue(processed, "a restarts-stream event did not invoke restart()")
    }
}
