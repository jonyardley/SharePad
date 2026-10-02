import Foundation

public struct PairingRecord: Equatable, Sendable {
    public let peerID: UUID
    public let peerName: String
    public let pairingID: UUID
    public let secret: LinkSecret
    public let pairedAt: TimeInterval
    public var lastConnectedAt: TimeInterval?

    public init(
        peerID: UUID,
        peerName: String,
        pairingID: UUID,
        secret: LinkSecret,
        pairedAt: TimeInterval,
        lastConnectedAt: TimeInterval? = nil
    ) {
        self.peerID = peerID
        self.peerName = peerName
        self.pairingID = pairingID
        self.secret = secret
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }

    static let formatVersion: UInt8 = 1

    func encoded() -> Data {
        var writer = ByteWriter()
        writer.u8(Self.formatVersion)
        writer.uuid(peerID)
        writer.text(peerName)
        writer.uuid(pairingID)
        writer.bytes(secret.bytes)
        writer.f64(pairedAt)
        writer.u8(lastConnectedAt == nil ? 0 : 1)
        writer.f64(lastConnectedAt ?? 0)
        return writer.data
    }

    static func decode(_ data: Data) throws -> PairingRecord {
        var reader = ByteReader(data)
        guard try reader.u8() == formatVersion else { throw WireError.truncated }
        let peerID = try reader.uuid()
        let peerName = try reader.text()
        let pairingID = try reader.uuid()
        guard let secret = try LinkSecret(bytes: reader.bytes(LinkSecret.byteCount)) else {
            throw WireError.truncated
        }
        let pairedAt = try reader.f64()
        let hasLastConnected = try reader.u8() == 1
        let lastConnected = try reader.f64()
        guard reader.rest().isEmpty else { throw WireError.truncated }
        return PairingRecord(
            peerID: peerID,
            peerName: peerName,
            pairingID: pairingID,
            secret: secret,
            pairedAt: pairedAt,
            lastConnectedAt: hasLastConnected ? lastConnected : nil
        )
    }
}

extension PairingRecord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "PairingRecord(peer: \(peerName) \(peerID), pairing: \(pairingID))"
    }

    public var debugDescription: String {
        description
    }
}

public struct PairingGrant: Equatable, Sendable {
    public let pairingID: UUID
    public let secret: LinkSecret

    public init(pairingID: UUID, secret: LinkSecret) {
        self.pairingID = pairingID
        self.secret = secret
    }
}
