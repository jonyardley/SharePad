import CryptoKit
import Foundation

/// Why a licence key did or did not activate, so the UI can guide the buyer.
enum LicenseCheck: Equatable {
    case valid
    case malformedKey
    case mismatch
}

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
        check(key: key, email: email) == .valid
    }

    // A malformed key (wrong length or not decodable) is almost always an
    // incomplete paste; a decodable 64-byte signature that fails to verify is a
    // wrong email. The UI tells the two apart so the buyer knows what to fix.
    func check(key: String, email: String) -> LicenseCheck {
        guard let signature = Self.decodeBase64URL(key), signature.count == 64 else {
            return .malformedKey
        }
        guard let publicKey,
              publicKey.isValidSignature(signature, for: Data(Self.normalize(email).utf8)) else {
            return .mismatch
        }
        return .valid
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
