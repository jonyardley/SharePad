import CryptoKit
@testable import SharePad
import XCTest

final class LicenseValidatorTests: XCTestCase {
    private func key(for name: String,
                     signedBy priv: Curve25519.Signing.PrivateKey) throws -> String {
        try priv.signature(for: Data(name.utf8)).base64EncodedString()
    }

    func testValidSignaturePasses() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let validator = LicenseValidator(publicKey: priv.publicKey)
        XCTAssertTrue(try validator.isValid(
            name: "Jon Yardley",
            key: key(for: "Jon Yardley", signedBy: priv)
        ))
    }

    func testTamperedNameFails() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let validator = LicenseValidator(publicKey: priv.publicKey)
        XCTAssertFalse(try validator.isValid(name: "Mallory", key: key(for: "Jon", signedBy: priv)))
    }

    func testForeignKeyFails() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let embedded = Curve25519.Signing.PrivateKey()
        let validator = LicenseValidator(publicKey: embedded.publicKey)
        XCTAssertFalse(try validator.isValid(name: "Jon", key: key(for: "Jon", signedBy: signer)))
    }

    func testGarbageKeyFails() {
        let validator = LicenseValidator(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        XCTAssertFalse(validator.isValid(name: "Jon", key: "not base64 !!"))
    }

    func testEmptyEmbeddedKeyValidatesNothing() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let validator = LicenseValidator(publicKeyBase64: "")
        XCTAssertFalse(try validator.isValid(name: "Jon", key: key(for: "Jon", signedBy: priv)))
    }
}
