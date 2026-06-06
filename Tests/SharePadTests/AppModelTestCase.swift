import AVFoundation
@testable import SharePad
import XCTest

/// Shared fixtures for the `AppModel` test suites. Split across files so no single
/// test class trips swiftlint's `type_body_length`.
@MainActor
class AppModelTestCase: XCTestCase {
    func device(_ id: String) -> CaptureDevice {
        CaptureDevice(id: id, name: "Device \(id)")
    }

    func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    func makeModel(
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
}
