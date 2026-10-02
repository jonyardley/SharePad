import Foundation

public typealias ConnectionID = Int

public struct ReceiverLink: Equatable, Sendable {
    public static let holdDuration: TimeInterval = 5

    public struct Peer: Equatable, Sendable {
        public let connection: ConnectionID
        public let hello: Hello

        public init(connection: ConnectionID, hello: Hello) {
            self.connection = connection
            self.hello = hello
        }
    }

    public enum Phase: Equatable, Sendable {
        case waiting
        case live(Peer)
        case holding(Peer, since: TimeInterval)
    }

    public enum CloseReason: Equatable, Sendable {
        case incompatible(peerVersion: UInt16)
        case replaced
    }

    public enum Event: Equatable, Sendable {
        case opened(ConnectionID)
        case helloReceived(ConnectionID, Hello)
        case closed(ConnectionID, at: TimeInterval)
        case holdElapsed(at: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        case sendHello(ConnectionID)
        case close(ConnectionID, CloseReason)
        case adopt(ConnectionID)
        case sendPause(ConnectionID)
        case sendResume(ConnectionID)
        case scheduleHoldCheck(after: TimeInterval)
        case endShare
    }

    public private(set) var phase: Phase = .waiting
    public private(set) var standby: [Peer] = []

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .opened(id):
            [.sendHello(id)]
        case let .helloReceived(id, hello):
            helloReceived(Peer(connection: id, hello: hello))
        case let .closed(id, now):
            closed(id, at: now)
        case let .holdElapsed(now):
            holdElapsed(at: now)
        }
    }

    private mutating func helloReceived(_ peer: Peer) -> [Effect] {
        let version = peer.hello.protocolVersion
        guard WireProtocol.supportedVersions.contains(version) else {
            return [.close(peer.connection, .incompatible(peerVersion: version))]
        }
        switch phase {
        case .waiting:
            phase = .live(peer)
            return [.adopt(peer.connection)]
        case let .live(current) where current.connection == peer.connection:
            return []
        case let .live(current) where current.hello.deviceID == peer.hello.deviceID:
            // A Wi-Fi drop can leave the old socket half-open after the iPad has
            // already reconnected; the newer connection is the real one.
            phase = .live(peer)
            return [.close(current.connection, .replaced), .adopt(peer.connection)]
        case let .holding(held, _) where held.hello.deviceID == peer.hello.deviceID:
            phase = .live(peer)
            return [.adopt(peer.connection)]
        case .live, .holding:
            return park(peer)
        }
    }

    private mutating func park(_ peer: Peer) -> [Effect] {
        let replaced = standby.firstIndex { $0.hello.deviceID == peer.hello.deviceID }
        guard let replaced else {
            standby.append(peer)
            return [.sendPause(peer.connection)]
        }
        let old = standby[replaced].connection
        standby[replaced] = peer
        return [.close(old, .replaced), .sendPause(peer.connection)]
    }

    private mutating func closed(_ id: ConnectionID, at now: TimeInterval) -> [Effect] {
        if case let .live(current) = phase, current.connection == id {
            phase = .holding(current, since: now)
            return [.scheduleHoldCheck(after: Self.holdDuration)]
        }
        standby.removeAll { $0.connection == id }
        return []
    }

    private mutating func holdElapsed(at now: TimeInterval) -> [Effect] {
        guard case let .holding(_, since) = phase, now - since >= Self.holdDuration else {
            return []
        }
        guard !standby.isEmpty else {
            phase = .waiting
            return [.endShare]
        }
        let next = standby.removeFirst()
        phase = .live(next)
        return [.endShare, .sendResume(next.connection), .adopt(next.connection)]
    }
}
