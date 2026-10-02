import Foundation

public struct PairingHealth: Equatable, Sendable {
    public static let failuresBeforeBroken = 3

    public enum Event: Equatable, Sendable {
        case handshakeFailed(UUID)
        case handshakeSucceeded(UUID)
        case peerForgot(UUID)
    }

    public enum Effect: Equatable, Sendable {
        case markBroken(UUID)
        case markHealthy(UUID)
    }

    private var consecutiveFailures: [UUID: Int] = [:]

    public init() {}

    public func isBroken(_ deviceID: UUID) -> Bool {
        consecutiveFailures[deviceID, default: 0] >= Self.failuresBeforeBroken
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .handshakeFailed(id):
            consecutiveFailures[id, default: 0] += 1
            return consecutiveFailures[id] == Self.failuresBeforeBroken ? [.markBroken(id)] : []
        case let .handshakeSucceeded(id):
            let wasBroken = isBroken(id)
            consecutiveFailures[id] = nil
            return wasBroken ? [.markHealthy(id)] : []
        case let .peerForgot(id):
            defer { consecutiveFailures[id] = Self.failuresBeforeBroken }
            return isBroken(id) ? [] : [.markBroken(id)]
        }
    }
}
