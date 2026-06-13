import CryptoKit
@testable import SharePad
import XCTest

final class LicenseValidatorTests: XCTestCase {
    private let privateKey = Curve25519.Signing.PrivateKey()

    private var validator: LicenseValidator {
        LicenseValidator(
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func key(for email: String) throws -> String {
        let message = Data(LicenseValidator.normalize(email).utf8)
        let signature = try privateKey.signature(for: message)
        return signature.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testValidKeyMatchesEmail() throws {
        XCTAssertTrue(try validator.isValid(
            key: key(for: "buyer@example.com"),
            email: "buyer@example.com"
        ))
    }

    func testEmailIsNormalizedBeforeChecking() throws {
        XCTAssertTrue(try validator.isValid(
            key: key(for: "buyer@example.com"),
            email: "  Buyer@Example.COM\n"
        ))
    }

    func testKeyWhitespaceIsTolerated() throws {
        XCTAssertTrue(try validator.isValid(
            key: " \(key(for: "buyer@example.com")) \n",
            email: "buyer@example.com"
        ))
    }

    func testWrongEmailFails() throws {
        XCTAssertFalse(try validator.isValid(
            key: key(for: "buyer@example.com"),
            email: "other@example.com"
        ))
    }

    func testTamperedKeyFails() throws {
        let original = try key(for: "buyer@example.com")
        let replacement: Character = original.first == "A" ? "B" : "A"
        let tampered = String(replacement) + original.dropFirst()
        XCTAssertFalse(validator.isValid(key: tampered, email: "buyer@example.com"))
    }

    func testGarbageKeyFails() {
        XCTAssertFalse(validator.isValid(key: "not-a-key!!", email: "buyer@example.com"))
    }

    func testBadPublicKeyRejectsEverythingAndIsNotConfigured() throws {
        let broken = LicenseValidator(publicKeyBase64: "garbage")
        XCTAssertFalse(broken.isConfigured)
        let signedKey = try key(for: "a@b.c")
        XCTAssertFalse(broken.isValid(key: signedKey, email: "a@b.c"))
    }

    func testProductionKeyIsConfigured() {
        XCTAssertTrue(LicenseValidator.production.isConfigured)
    }
}
