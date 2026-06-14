import AVFoundation
import CryptoKit
@testable import SharePad
import XCTest

@MainActor
final class LicenseGateTests: GateTestCase {
    func testFirstLaunchIsRecordedOnce() throws {
        let prefs = try ephemeralPreferences()
        _ = makeModel(preferences: prefs)
        let recorded = try XCTUnwrap(prefs.firstLaunchDate)
        _ = makeModel(preferences: prefs)
        XCTAssertEqual(prefs.firstLaunchDate, recorded)
    }

    func testFreshInstallIsInTrial() throws {
        let model = try makeModel(preferences: ephemeralPreferences())
        XCTAssertEqual(model.entitlement, .trial(daysLeft: EntitlementClock.trialDays))
    }

    func testOldInstallIsExpired() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let model = makeModel(preferences: prefs)
        XCTAssertEqual(model.entitlement, .trialExpired)
    }

    func testEnterValidLicensePersistsAndLicenses() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let model = makeModel(preferences: prefs)
        let key = try signedKey(for: "buyer@example.com")
        XCTAssertTrue(model.enterLicense(email: " Buyer@Example.com ", key: key))
        XCTAssertEqual(model.entitlement, .licensed)
        XCTAssertEqual(prefs.licenseEmail, "buyer@example.com")
        XCTAssertNotNil(prefs.licenseKey)
    }

    func testEnterInvalidLicenseIsRejected() throws {
        let prefs = try ephemeralPreferences()
        let model = makeModel(preferences: prefs)
        XCTAssertFalse(model.enterLicense(email: "buyer@example.com", key: "bogus"))
        XCTAssertNotEqual(model.entitlement, .licensed)
        XCTAssertNil(prefs.licenseEmail)
        XCTAssertNil(prefs.licenseKey)
    }

    func testKeyForDifferentEmailIsRejected() throws {
        let prefs = try ephemeralPreferences()
        let model = makeModel(preferences: prefs)
        let key = try signedKey(for: "other@example.com")
        XCTAssertFalse(model.enterLicense(email: "buyer@example.com", key: key))
        XCTAssertNotEqual(model.entitlement, .licensed)
        XCTAssertNil(prefs.licenseEmail)
    }

    func testStoredLicenseSurvivesRelaunch() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        prefs.licenseEmail = "buyer@example.com"
        prefs.licenseKey = try signedKey(for: "buyer@example.com")
        XCTAssertEqual(makeModel(preferences: prefs).entitlement, .licensed)
    }

    func testOverlayAppearsAfterSessionLimitWhenExpired() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        XCTAssertTrue(model.isWindowVisible)
        await poll { model.isTrialOverlayShown }
        XCTAssertEqual(window.trialOverlayStates, [true])
        XCTAssertTrue(model.isTrialOverlayShown)
    }

    func testCountdownArmsWhenExpiredSessionStarts() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 100)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        XCTAssertNotNil(model.sessionEndsAt)
        XCTAssertNotNil(try XCTUnwrap(window.trialCountdownDeadlines.first))
        XCTAssertEqual(window.trialOverlayStates, []) // counting down, not paused yet
    }

    func testCountdownClearsWhenWindowHidden() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 100)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        model.toggleWindow()
        XCTAssertNil(model.sessionEndsAt)
        XCTAssertNil(try XCTUnwrap(window.trialCountdownDeadlines.last))
    }

    func testCountdownClearsWhenOverlayFires() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        await poll { model.isTrialOverlayShown }
        XCTAssertNil(model.sessionEndsAt)
        XCTAssertEqual(window.trialOverlayStates, [true])
        // Armed (non-nil) then cleared (nil) immediately before the pause overlay.
        XCTAssertNotNil(try XCTUnwrap(window.trialCountdownDeadlines.first))
        XCTAssertNil(try XCTUnwrap(window.trialCountdownDeadlines.last))
    }

    func testSameDeviceResumesRemainingOnReplug() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, now: { clock }, sessionLimit: 100)

        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        let armed = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        XCTAssertEqual(armed.timeIntervalSinceReferenceDate, 1100, accuracy: 0.01)

        clock = Date(timeIntervalSinceReferenceDate: 1030) // 30s of sharing
        await model.reconcile(devices: []) // unplug — freezes 70s remaining
        XCTAssertNil(model.sessionEndsAt)

        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")]) // replug at t=1030
        let resumed = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        // 70s left resumes → deadline 1030+70=1100, NOT a fresh 1030+100=1130
        XCTAssertEqual(resumed.timeIntervalSinceReferenceDate, 1100, accuracy: 0.01)
    }

    func testDifferentDeviceStartsFreshSession() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, now: { clock }, sessionLimit: 100)

        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        clock = Date(timeIntervalSinceReferenceDate: 1030)
        await model.reconcile(devices: []) // unplug A

        await model.reconcile(devices: [CaptureDevice(id: "b", name: "iPad 2")]) // different iPad
        let fresh = try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
        XCTAssertEqual(fresh.timeIntervalSinceReferenceDate, 1130, accuracy: 0.01) // full 100s
    }

    func testManualSwitchToDifferentDeviceStartsFresh() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, now: { clock }, sessionLimit: 100)
        await model.reconcile(devices: [
            CaptureDevice(id: "a", name: "iPad"),
            CaptureDevice(id: "b", name: "iPad 2"),
        ])
        XCTAssertEqual(try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
            .timeIntervalSinceReferenceDate, 1100, accuracy: 0.01) // A counting

        clock = Date(timeIntervalSinceReferenceDate: 1040)
        await model.switchTo(deviceID: "b")
        // Picking a different iPad gets a fresh budget → 1040+100=1140, not A's 1100.
        XCTAssertEqual(try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
            .timeIntervalSinceReferenceDate, 1140, accuracy: 0.01)
    }

    func testSwitchingBackToADeviceResumesItsRemainingBudget() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, now: { clock }, sessionLimit: 100)
        await model.reconcile(devices: [
            CaptureDevice(id: "a", name: "iPad"),
            CaptureDevice(id: "b", name: "iPad 2"),
        ])
        // A armed at 1000 → deadline 1100.
        clock = Date(timeIntervalSinceReferenceDate: 1040)
        await model.switchTo(deviceID: "b") // A froze with 60s left; B fresh → 1040+100=1140.
        XCTAssertEqual(try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
            .timeIntervalSinceReferenceDate, 1140, accuracy: 0.01)
        clock = Date(timeIntervalSinceReferenceDate: 1060)
        await model.switchTo(deviceID: "a")
        // A RESUMES its 60s → deadline 1060+60=1120, NOT a fresh 1060+100=1160.
        XCTAssertEqual(try XCTUnwrap(window.trialCountdownDeadlines.last ?? nil)
            .timeIntervalSinceReferenceDate, 1120, accuracy: 0.01)
    }

    func testExhaustedSessionPausesImmediatelyOnSameDeviceReplug() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        await poll { model.isTrialOverlayShown } // budget spent, paused
        XCTAssertTrue(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true])

        await model.reconcile(devices: []) // unplug clears the overlay display
        XCTAssertFalse(model.isTrialOverlayShown)

        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")]) // replug
        // Same iPad with 0 budget → pauses immediately, no fresh countdown.
        XCTAssertTrue(model.isTrialOverlayShown)
        XCTAssertNil(model.sessionEndsAt)
        XCTAssertEqual(window.trialOverlayStates, [true, false, true])
    }

    func testNoOverlayDuringTrial() async throws {
        let window = FakeShareWindow()
        let model = try makeModel(
            preferences: ephemeralPreferences(),
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        // Drain any scheduled work, then confirm the overlay never fired.
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        XCTAssertEqual(window.trialOverlayStates, [])
    }

    func testHidingWindowClearsOverlayAndTimer() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        await poll { window.trialOverlayStates == [true] }
        model.toggleWindow()
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }

    func testEnteringLicenseClearsOverlay() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        await poll { window.trialOverlayStates == [true] }
        let key = try signedKey(for: "buyer@example.com")
        XCTAssertTrue(model.enterLicense(email: "buyer@example.com", key: key))
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }

    func testFailedDeviceSwitchClearsTrialSession() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let capture = FakeCaptureController()
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            capture: capture,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [
            CaptureDevice(id: "a", name: "iPad"),
            CaptureDevice(id: "b", name: "iPad 2"),
        ])
        await poll { window.trialOverlayStates == [true] }
        XCTAssertEqual(window.trialOverlayStates, [true])

        capture.startResult = false
        await model.switchTo(deviceID: "b")
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }

    // A direct hot-swap (.switchTo, no intervening teardown) must clear the prior
    // device's overlay AND re-arm the gate for the new device — the auto-connect path
    // reuses the visible window without a hide cycle.
    func testHotSwapClearsAndRearmsTrialGate() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(
            preferences: prefs,
            window: window,
            sleep: { _ in },
            sessionLimit: 100
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        await poll { window.trialOverlayStates == [true] } // device A's overlay fired

        await model.reconcile(devices: [CaptureDevice(id: "b", name: "iPad 2")]) // hot-swap A→B
        XCTAssertFalse(model.isTrialOverlayShown) // A's overlay cleared on swap
        await poll { window.trialOverlayStates == [
            true,
            false,
            true,
        ] } // B's session re-armed + fired
        XCTAssertTrue(model.isTrialOverlayShown)
    }

    private func poll(
        timeoutIterations: Int = 100_000,
        _ predicate: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< timeoutIterations {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("poll condition never satisfied", file: file, line: line)
    }
}
