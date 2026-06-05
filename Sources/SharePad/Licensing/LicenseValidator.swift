import CryptoKit
import Foundation

/// Offline check: the key is a base64 Ed25519 signature of the licensee name (licensing.md §3.1).
struct LicenseValidator: KeyValidating {
    private let publicKey: Curve25519.Signing.PublicKey?

    init(publicKeyBase64: String) {
        publicKey = Data(base64Encoded: publicKeyBase64)
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    func isValid(name: String, key: String) -> Bool {
        guard let publicKey, let signature = Data(base64Encoded: key) else { return false }
        return publicKey.isValidSignature(signature, for: Data(name.utf8))
    }
}
