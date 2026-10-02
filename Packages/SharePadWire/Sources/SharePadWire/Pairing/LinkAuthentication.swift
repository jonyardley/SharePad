import CryptoKit
import Foundation

public enum LinkCredential: Equatable, Sendable {
    case pairing(proof: Data)
    case paired(pairingID: UUID, proof: Data)

    static let proofLength = SHA256.byteCount

    public static func pairing(code: PairingCode, exporter: Data) -> LinkCredential {
        .pairing(proof: LinkAuthentication.proof(
            key: code.keys.proofKey,
            pairingID: nil,
            exporter: exporter
        ))
    }

    public static func paired(_ record: PairingRecord, exporter: Data) -> LinkCredential {
        .paired(
            pairingID: record.pairingID,
            proof: LinkAuthentication.proof(
                key: record.secret.keys.proofKey,
                pairingID: record.pairingID,
                exporter: exporter
            )
        )
    }
}

// The TLS server cannot see which PSK the client used, so the client proves it with an
// HMAC over this session's exported keying material (RFC 5705): no replay, no borrowing.
public enum LinkAuthentication {
    public enum Peer: Equatable, Sendable {
        case pairing
        case paired(PairingRecord)
    }

    public static let exporterLabel = "EXPORTER-co.sharepad.wire.link-proof"
    public static let exporterLength = 32

    public static func verify(
        _ credential: LinkCredential,
        exporter: Data,
        pairingCode: PairingCode?,
        paired: [PairingRecord]
    ) -> Peer? {
        switch credential {
        case let .pairing(proof):
            guard let pairingCode else { return nil }
            return isValid(
                proof,
                key: pairingCode.keys.proofKey,
                pairingID: nil,
                exporter: exporter
            )
                ? .pairing : nil
        case let .paired(pairingID, proof):
            guard let record = paired.first(where: { $0.pairingID == pairingID })
            else { return nil }
            return isValid(
                proof,
                key: record.secret.keys.proofKey,
                pairingID: pairingID,
                exporter: exporter
            )
                ? .paired(record) : nil
        }
    }

    static func proof(key: SymmetricKey, pairingID: UUID?, exporter: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: message(pairingID: pairingID, exporter: exporter),
            using: key
        ))
    }

    private static func isValid(_ proof: Data, key: SymmetricKey, pairingID: UUID?,
                                exporter: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: message(pairingID: pairingID, exporter: exporter),
            using: key
        )
    }

    private static func message(pairingID: UUID?, exporter: Data) -> Data {
        var writer = ByteWriter()
        writer.bytes(Data("co.sharepad.wire.link-proof.v1".utf8))
        if let pairingID {
            writer.u8(1)
            writer.uuid(pairingID)
        } else {
            writer.u8(0)
        }
        writer.bytes(exporter)
        return writer.data
    }
}

public enum PairingMessage: Equatable, Sendable {
    case authenticate(LinkCredential)
    case grant(PairingGrant)
    case stored(pairingID: UUID)

    // Separate from WireMessage so the stream enum stays exhaustive for its users;
    // codes are permanent and sit clear of the stream range.
    static let authenticateCode: UInt8 = 16
    static let grantCode: UInt8 = 17
    static let storedCode: UInt8 = 18

    public static func handles(_ typeCode: UInt8) -> Bool {
        (authenticateCode ... storedCode).contains(typeCode)
    }

    var typeCode: UInt8 {
        switch self {
        case .authenticate: Self.authenticateCode
        case .grant: Self.grantCode
        case .stored: Self.storedCode
        }
    }

    public func encoded() -> Data {
        var body = ByteWriter()
        switch self {
        case let .authenticate(.pairing(proof)):
            body.u8(0)
            body.bytes(proof)
        case let .authenticate(.paired(pairingID, proof)):
            body.u8(1)
            body.uuid(pairingID)
            body.bytes(proof)
        case let .grant(grant):
            body.uuid(grant.pairingID)
            body.bytes(grant.secret.bytes)
        case let .stored(pairingID):
            body.uuid(pairingID)
        }
        var out = ByteWriter()
        out.u8(typeCode)
        out.u32(UInt32(body.data.count))
        out.bytes(body.data)
        return out.data
    }

    public static func decode(typeCode: UInt8, payload: Data) throws -> PairingMessage {
        var reader = ByteReader(payload)
        let message: PairingMessage
        switch typeCode {
        case authenticateCode:
            switch try reader.u8() {
            case 0:
                message =
                    try .authenticate(.pairing(proof: reader.bytes(LinkCredential.proofLength)))
            case 1:
                message = try .authenticate(.paired(
                    pairingID: reader.uuid(),
                    proof: reader.bytes(LinkCredential.proofLength)
                ))
            default:
                throw WireError.unknownMessageType(typeCode)
            }
        case grantCode:
            let pairingID = try reader.uuid()
            guard let secret = try LinkSecret(bytes: reader.bytes(LinkSecret.byteCount)) else {
                throw WireError.truncated
            }
            message = .grant(PairingGrant(pairingID: pairingID, secret: secret))
        case storedCode:
            message = try .stored(pairingID: reader.uuid())
        default:
            throw WireError.unknownMessageType(typeCode)
        }
        guard reader.rest().isEmpty else { throw WireError.truncated }
        return message
    }
}

extension PairingMessage: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authenticate(.pairing): "authenticate(pairing)"
        case let .authenticate(.paired(pairingID, _)): "authenticate(paired \(pairingID))"
        case let .grant(grant): "grant(\(grant.pairingID))"
        case let .stored(pairingID): "stored(\(pairingID))"
        }
    }
}

// Per connection on the Mac: nothing reaches the stream or pairing rules until the
// peer has proved a credential and sent a hello that matches it.
public struct LinkGate: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case awaitingCredential
        case awaitingHello(LinkAuthentication.Peer)
        case open(LinkAuthentication.Peer, Hello)
        case closed
    }

    public enum Event: Equatable, Sendable {
        case credentialChecked(LinkAuthentication.Peer?)
        case helloReceived(Hello)
        case streamMessage
        case pairingMessage
    }

    public enum CloseReason: Equatable, Sendable {
        case badCredential
        case unauthenticated
        case identityMismatch
        case unexpectedCredential
        case notPaired
        case notPairing
    }

    public enum Decision: Equatable, Sendable {
        case wait
        case admitHello(LinkAuthentication.Peer, Hello)
        case pass
        case close(CloseReason)
    }

    public private(set) var phase: Phase = .awaitingCredential
    private var closeReason: CloseReason = .unauthenticated

    public init() {}

    public mutating func reduce(_ event: Event) -> Decision {
        switch phase {
        case .closed: .close(closeReason)
        case .awaitingCredential: awaitingCredential(event)
        case let .awaitingHello(peer): awaitingHello(peer, event)
        case let .open(peer, hello): open(peer, hello, event)
        }
    }

    private mutating func awaitingCredential(_ event: Event) -> Decision {
        guard case let .credentialChecked(peer) = event else { return close(.unauthenticated) }
        guard let peer else { return close(.badCredential) }
        return admitCredential(peer)
    }

    private mutating func awaitingHello(_ peer: LinkAuthentication.Peer,
                                        _ event: Event) -> Decision {
        switch event {
        case let .helloReceived(hello): admitHello(hello, from: peer)
        case .credentialChecked: close(.unexpectedCredential)
        case .streamMessage, .pairingMessage: close(.unauthenticated)
        }
    }

    private mutating func open(_ peer: LinkAuthentication.Peer, _ current: Hello,
                               _ event: Event) -> Decision {
        switch (peer, event) {
        case let (_, .helloReceived(hello)):
            hello.deviceID == current.deviceID ? .pass : close(.identityMismatch)
        case (_, .credentialChecked):
            close(.unexpectedCredential)
        case (.pairing, .pairingMessage), (.paired, .streamMessage):
            .pass
        case (.pairing, .streamMessage):
            close(.notPaired)
        case (.paired, .pairingMessage):
            close(.notPairing)
        }
    }

    private mutating func admitCredential(_ peer: LinkAuthentication.Peer) -> Decision {
        phase = .awaitingHello(peer)
        return .wait
    }

    private mutating func admitHello(_ hello: Hello,
                                     from peer: LinkAuthentication.Peer) -> Decision {
        guard Self.binds(hello, to: peer) else { return close(.identityMismatch) }
        phase = .open(peer, hello)
        return .admitHello(peer, hello)
    }

    private mutating func close(_ reason: CloseReason) -> Decision {
        phase = .closed
        closeReason = reason
        return .close(reason)
    }

    private static func binds(_ hello: Hello, to peer: LinkAuthentication.Peer) -> Bool {
        switch peer {
        case .pairing: true
        case let .paired(record): hello.deviceID == record.peerID
        }
    }
}
