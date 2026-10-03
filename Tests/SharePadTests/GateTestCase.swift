import AVFoundation
import CryptoKit
@testable import SharePad
import XCTest

@MainActor
class GateTestCase: XCTestCase {
    let privateKey = Curve25519.Signing.PrivateKey()
    let day: TimeInterval = 86400

    func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    func validator() -> LicenseValidator {
        LicenseValidator(
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    func signedKey(for email: String) throws -> String {
        let message = Data(LicenseValidator.normalize(email).utf8)
        return try privateKey.signature(for: message).base64EncodedString()
    }

    func makeModel(
        preferences: Preferences,
        capture: FakeCaptureController = FakeCaptureController(),
        window: FakeShareWindow = FakeShareWindow(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        sessionLimit: TimeInterval = 5 * 60,
        wireless: WirelessFeeding? = nil,
        permission: AVAuthorizationStatus = .notDetermined
    ) -> AppModel {
        AppModel(
            preferences: preferences,
            capture: capture,
            wireless: wireless,
            window: window,
            sleep: sleep,
            validator: validator(),
            now: now,
            sessionLimit: sessionLimit,
            permission: permission
        )
    }

    func poll(
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
