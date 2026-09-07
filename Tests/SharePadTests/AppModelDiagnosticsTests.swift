import Foundation
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
        let result = model.enterLicense(email: "buyer@example.com", key: "not-a-real-key")
        XCTAssertEqual(result, .malformedKey)
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

    func testDisabledReporterSendsNothing() throws {
        let requested = expectation(description: "a request was issued")
        requested.isInverted = true
        RecordingURLProtocol.onRequest = { _ in requested.fulfill() }
        defer { RecordingURLProtocol.onRequest = nil }
        let prefs = try ephemeralPreferences()
        prefs.diagnosticsEnabled = false
        let reporter = DiagnosticsReporter(preferences: prefs, session: recordingSession())
        reporter.report(.shareLost)
        wait(for: [requested], timeout: 0.3)
    }

    func testEnabledReporterSendsOnePost() throws {
        let requested = expectation(description: "a request was issued")
        let box = RequestBox()
        RecordingURLProtocol.onRequest = { request in
            box.request = request
            requested.fulfill()
        }
        defer { RecordingURLProtocol.onRequest = nil }
        let prefs = try ephemeralPreferences()
        prefs.diagnosticsEnabled = true
        let reporter = DiagnosticsReporter(preferences: prefs, session: recordingSession())
        reporter.report(.shareLost)
        wait(for: [requested], timeout: 1.0)
        XCTAssertEqual(box.request?.httpMethod, "POST")
        XCTAssertEqual(box.request?.url?.absoluteString, "https://telemetry.sharepad.co/report")
        let userAgent = box.request?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertTrue(userAgent?.contains("SharePad") ?? false)
    }

    func testSetDiagnosticsEnabledPersistsAndRefreshes() throws {
        let spy = SpyDiagnosticsReporter()
        let prefs = try ephemeralPreferences()
        let model = makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: prefs,
            reporter: spy
        )
        XCTAssertFalse(model.diagnosticsEnabled)
        model.setDiagnosticsEnabled(true)
        XCTAssertTrue(model.diagnosticsEnabled)
        XCTAssertTrue(prefs.diagnosticsEnabled)
        XCTAssertEqual(spy.refreshCount, 1)
    }

    private func recordingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Carries a captured request from the URLProtocol callback back to the test.
/// @unchecked Sendable: written once on the protocol's queue, read after `wait`.
final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}

/// Intercepts the reporter's POST so a test can assert whether, and what, it sent
/// without touching the network.
class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var onRequest: (@Sendable (URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        onRequest?(request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url,
           let response = HTTPURLResponse(
               url: url, statusCode: 204, httpVersion: nil, headerFields: nil
           ) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
