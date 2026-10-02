import Foundation

public extension StreamSender {
    enum Security: Sendable {
        case unauthenticated
        case paired([PairingRecord])
    }

    enum PairedEvent: Equatable, Sendable {
        case connected(macID: UUID)
        case handshakeFailed(macID: UUID)
    }
}
