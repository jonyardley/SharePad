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
            thumbnailLayer: AVSampleBufferDisplayLayer()
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
        XCTAssertFalse(model.isLive)
        XCTAssertTrue(model.failed)
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
