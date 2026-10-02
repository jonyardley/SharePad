import Foundation
import SharePadWire

struct PairedIPad: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let lastConnectedAt: Date?
    let needsPairing: Bool
}

struct PairingInvitation: Equatable, Sendable {
    let typedCode: String
    let link: URL
    let expiresAt: Date
}

// What the pairing window may show: never the secret, only the one-time code.
enum PairingProgress: Equatable, Sendable {
    case closed
    case offering(PairingInvitation)
    case pairing(PairingInvitation, iPad: String)
    case paired(iPad: String)
    case expired
    case interrupted

    init(_ phase: PairingWindow.Phase) {
        switch phase {
        case .closed:
            self = .closed
        case let .offering(offer):
            self = Self.invitation(offer).map(Self.offering) ?? .interrupted
        case let .granting(offer, _, peer):
            self = Self.invitation(offer)
                .map { .pairing($0, iPad: peer.deviceName) } ?? .interrupted
        case let .paired(record):
            self = .paired(iPad: record.peerName)
        case .expired:
            self = .expired
        case .interrupted:
            self = .interrupted
        }
    }

    private static func invitation(_ offer: PairingOffer) -> PairingInvitation? {
        guard let link = offer.code.invitationURL else { return nil }
        return PairingInvitation(
            typedCode: offer.code.typed,
            link: link,
            expiresAt: Date(timeIntervalSince1970: offer.issuedAt + PairingOffer.lifetime)
        )
    }
}

extension PairedIPad {
    init(_ record: PairingRecord, needsPairing: Bool) {
        self.init(
            id: record.peerID,
            name: record.peerName,
            lastConnectedAt: record.lastConnectedAt.map(Date.init(timeIntervalSince1970:)),
            needsPairing: needsPairing
        )
    }
}
