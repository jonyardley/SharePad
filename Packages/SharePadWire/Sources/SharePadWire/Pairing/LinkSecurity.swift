import CryptoKit
import Foundation
import Network
import Security

public enum LinkSecurity: Sendable {
    case unauthenticated
    case pairing(PairingCode)
    case paired(PairingRecord)
    case server(pairingCode: PairingCode?, paired: [PairingRecord])

    // ECDHE_PSK_WITH_CHACHA20_POLY1305: PSK is TLS 1.2 only here (forums thread 688508)
    // and the default PSK suite has no forward secrecy (open question 3).
    public static let cipherSuite: UInt16 = 0xCCAC

    static let pairingIdentity = Data("co.sharepad.pair.v1".utf8)

    static func identity(for record: PairingRecord) -> Data {
        Data("co.sharepad.link.v1:\(record.pairingID.uuidString)".utf8)
    }

    var keys: [(key: SymmetricKey, identity: Data)] {
        switch self {
        case .unauthenticated:
            []
        case let .pairing(code):
            [(code.keys.tlsKey, Self.pairingIdentity)]
        case let .paired(record):
            [(record.secret.keys.tlsKey, Self.identity(for: record))]
        case let .server(code, paired):
            (code.map { [($0.keys.tlsKey, Self.pairingIdentity)] } ?? [])
                + paired.map { ($0.secret.keys.tlsKey, Self.identity(for: $0)) }
        }
    }

    func tlsOptions() -> NWProtocolTLS.Options? {
        if case .unauthenticated = self { return nil }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        // Fails closed: without the pinned suite no key is added, so every handshake fails.
        guard let suite = tls_ciphersuite_t(rawValue: Self.cipherSuite) else { return tls }
        sec_protocol_options_append_tls_ciphersuite(options, suite)
        for (key, identity) in keys {
            sec_protocol_options_add_pre_shared_key(
                options,
                key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
                identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
            )
        }
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        return tls
    }
}

public extension NWError {
    var isLinkAuthenticationFailure: Bool {
        if case .tls = self { return true }
        return false
    }
}
