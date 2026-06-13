import AVFoundation
import CryptoKit
@testable import SharePad
import XCTest

@MainActor
final class LicenseGateTests: XCTestCase {
    private let privateKey = Curve25519.Signing.PrivateKey()
    private let day: TimeInterval = 86400

    private func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    private func validator() -> LicenseValidator {
        LicenseValidator(
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signedKey(for email: String) throws -> String {
        let message = Data(LicenseValidator.normalize(email).utf8)
        return try privateKey.signature(for: message).base64EncodedString()
    }

    private func makeModel(
        preferences: Preferences,
        capture: FakeCaptureController = FakeCaptureController(),
        window: FakeShareWindow = FakeShareWindow(),
        now: @escaping () -> Date = Date.init,
        sessionLimit: TimeInterval = 5 * 60
    ) -> AppModel {
        AppModel(
            preferences: preferences,
            capture: capture,
            window: window,
            thumbnailLayer: AVSampleBufferDisplayLayer(),
            validator: validator(),
            now: now,
            sessionLimit: sessionLimit
        )
    }

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
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        XCTAssertTrue(model.isWindowVisible)
        try await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(window.trialOverlayStates, [true])
        XCTAssertTrue(model.isTrialOverlayShown)
    }

    func testNoOverlayDuringTrial() async throws {
        let window = FakeShareWindow()
        let model = try makeModel(
            preferences: ephemeralPreferences(),
            window: window,
            sessionLimit: 0.05
        )
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(window.trialOverlayStates, [])
    }

    func testHidingWindowClearsOverlayAndTimer() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.5))
        model.toggleWindow()
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }

    func testEnteringLicenseClearsOverlay() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.5))
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
            sessionLimit: 0.05
        )
        await model.reconcile(devices: [
            CaptureDevice(id: "a", name: "iPad"),
            CaptureDevice(id: "b", name: "iPad 2"),
        ])
        try await Task.sleep(for: .seconds(0.5))
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
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(window.trialOverlayStates, [true]) // device A's overlay fired

        await model.reconcile(devices: [CaptureDevice(id: "b", name: "iPad 2")]) // hot-swap A→B
        XCTAssertFalse(model.isTrialOverlayShown) // A's overlay cleared on swap
        try await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(window.trialOverlayStates, [
            true,
            false,
            true,
        ]) // B's session re-armed + fired
        XCTAssertTrue(model.isTrialOverlayShown)
    }
}
