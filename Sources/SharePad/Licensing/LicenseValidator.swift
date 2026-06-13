import CryptoKit
import Foundation

struct LicenseValidator {
    private let publicKey: Curve25519.Signing.PublicKey?

    static let production = LicenseValidator(publicKeyBase64: License.publicKeyBase64)

    init(publicKeyBase64: String) {
        publicKey = Data(base64Encoded: publicKeyBase64)
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    // testProductionKeyIsConfigured guards against shipping a malformed embedded key.
    var isConfigured: Bool {
        publicKey != nil
    }

    func isValid(key: String, email: String) -> Bool {
        guard let publicKey, let signature = Self.decodeBase64URL(key) else { return false }
        return publicKey.isValidSignature(signature, for: Data(Self.normalize(email).utf8))
    }

    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decodeBase64URL(_ key: String) -> Data? {
        var base64 = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }
}
