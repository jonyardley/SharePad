import Foundation
import MetricKit

/// A domain non-fatal MetricKit cannot see. Bare names only, never any payload,
/// so nothing about the user, their device, or their content is ever transmitted.
enum DiagnosticEvent: String {
    case retryExhausted
    case restartFailed
    case shareLost
    case licenseEntryFailed
}

protocol DiagnosticsReporting: Sendable {
    func report(_ event: DiagnosticEvent)
    /// Add or remove the MetricKit subscription to match the current opt-in state.
    @MainActor func refreshSubscription()
}

/// The default in tests and wherever telemetry is off by construction: does nothing.
struct DisabledDiagnosticsReporter: DiagnosticsReporting {
    func report(_: DiagnosticEvent) {}
    func refreshSubscription() {}
}

extension DiagnosticsReporting where Self == DisabledDiagnosticsReporter {
    static var disabled: DisabledDiagnosticsReporter {
        DisabledDiagnosticsReporter()
    }
}

/// First-party, opt-in crash/diagnostic reporting (specs/telemetry.md). Off unless
/// the user turns it on; sends anonymous JSON to the telemetry Worker, never any
/// content, licence, or device identifier.
///
/// @unchecked Sendable: `preferences` is a value type over the thread-safe
/// `UserDefaults`; `isSubscribed` is touched only from the main actor
/// (`refreshSubscription`); `send` is stateless and fire-and-forget.
final class DiagnosticsReporter: NSObject, DiagnosticsReporting, @unchecked Sendable {
    static let shared = DiagnosticsReporter()

    private static let endpoint = URL(string: "https://telemetry.sharepad.co/report")
    private let preferences: Preferences
    private let session: URLSession
    private var isSubscribed = false

    init(preferences: Preferences = Preferences(), session: URLSession = .shared) {
        self.preferences = preferences
        self.session = session
    }

    func report(_ event: DiagnosticEvent) {
        guard preferences.diagnosticsEnabled else { return }
        send(kind: "event", name: event.rawValue, payloadJSON: nil)
    }

    @MainActor
    func refreshSubscription() {
        let wanted = preferences.diagnosticsEnabled
        guard wanted != isSubscribed else { return }
        if wanted {
            MXMetricManager.shared.add(self)
        } else {
            MXMetricManager.shared.remove(self)
        }
        isSubscribed = wanted
    }

    // ── Pure body encoding (unit-tested; the contract the Worker consumes) ──
    static func encodeBody(kind: String, name: String, appVersion: String,
                           osVersion: String, payloadJSON: Data?) -> Data? {
        var body: [String: Any] = [
            "kind": kind,
            "name": name,
            "appVersion": appVersion,
            "osVersion": osVersion,
        ]
        if let payloadJSON,
           let object = try? JSONSerialization.jsonObject(with: payloadJSON) {
            body["payload"] = object
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func send(kind: String, name: String, payloadJSON: Data?) {
        guard let endpoint = Self.endpoint,
              let data = Self.encodeBody(
                  kind: kind, name: name,
                  appVersion: Self.appVersion, osVersion: Self.osVersion,
                  payloadJSON: payloadJSON
              ) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SharePad/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        // Fire-and-forget: a failed or slow POST must never touch the app's behaviour.
        session.dataTask(with: request).resume()
    }
}

extension DiagnosticsReporter: MXMetricManagerSubscriber {
    // Required by MXMetricManagerSubscriber (the diagnostic method is the optional
    // one). We want diagnostics only, so metric payloads are intentionally ignored.
    func didReceive(_: [MXMetricPayload]) {}

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard preferences.diagnosticsEnabled else { return }
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                // Never the raw terminationReason: it can embed a home-directory path
                // (dyld/code-signing failures), which would put the account name into
                // the anonymous time series. The full text still goes to R2.
                let signal = crash.signal.map { "signal-\($0.intValue)" }
                let exception = crash.exceptionType.map { "exception-\($0.intValue)" }
                send(kind: "crash", name: signal ?? exception ?? "crash",
                     payloadJSON: crash.jsonRepresentation())
            }
            for hang in payload.hangDiagnostics ?? [] {
                send(kind: "hang", name: "hang", payloadJSON: hang.jsonRepresentation())
            }
        }
    }
}
