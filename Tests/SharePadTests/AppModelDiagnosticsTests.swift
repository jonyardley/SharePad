@testable import SharePad
import XCTest

@MainActor
final class AppModelDiagnosticsTests: AppModelTestCase {
    func testShareLostEmitsEvent() async throws {
        let spy = SpyDiagnosticsReporter()
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            reporter: spy
        )
        await model.reconcile(devices: [device("a")]) // auto-shows → sharing
        await model.reconcile(devices: []) // unplug while sharing → lost share
        XCTAssertTrue(spy.events.contains(.shareLost))
    }

    func testLicenseEntryFailureEmitsEvent() throws {
        let spy = SpyDiagnosticsReporter()
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            reporter: spy
        )
        XCTAssertFalse(model.enterLicense(email: "buyer@example.com", key: "not-a-real-key"))
        XCTAssertEqual(spy.events, [.licenseEntryFailed])
    }

    func testRestartFailureEmitsEvent() async throws {
        let capture = FakeCaptureController()
        let spy = SpyDiagnosticsReporter()
        let model = try makeModel(
            capture: capture,
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            reporter: spy
        )
        await model.reconcile(devices: [device("a")]) // connect
        capture.resumeResult = false
        capture.startResult = false // resume and fallback start both fail
        await model.restart()
        XCTAssertTrue(spy.events.contains(.restartFailed))
    }

    func testRetryExhaustionEmitsEvent() async throws {
        let capture = FakeCaptureController()
        capture.startResult = false // every connect attempt fails to go live
        let spy = SpyDiagnosticsReporter()
        let model = try makeModel(
            capture: capture,
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            reporter: spy
        )
        await model.reconcile(devices: [device("a")]) // auto-connect → retry loop
        await model.retryTask?.value
        XCTAssertTrue(spy.events.contains(.retryExhausted))
    }

    func testEncodeBodyEventOmitsPayload() throws {
        let data = try XCTUnwrap(DiagnosticsReporter.encodeBody(
            kind: "event", name: "shareLost", appVersion: "1.2.0",
            osVersion: "14.5", payloadJSON: nil
        ))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "event")
        XCTAssertEqual(object["name"] as? String, "shareLost")
        XCTAssertEqual(object["appVersion"] as? String, "1.2.0")
        XCTAssertEqual(object["osVersion"] as? String, "14.5")
        XCTAssertNil(object["payload"])
    }

    func testEncodeBodyCrashIncludesPayload() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["stack": "top"])
        let data = try XCTUnwrap(DiagnosticsReporter.encodeBody(
            kind: "crash", name: "SIGSEGV", appVersion: "1.2.0",
            osVersion: "14.5", payloadJSON: payload
        ))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["payload"] as? [String: Any])?["stack"] as? String, "top")
    }
}
