import Foundation

public struct SenderLink: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case searching
        case connecting(String)
        case handshaking(String)
        case live(String)
        case paused(String)
        case incompatible(String, peerVersion: UInt16)
    }

    public enum Event: Equatable, Sendable {
        case start
        case stop
        case found([String])
        case connectionReady
        case helloReceived(Hello)
        case pauseReceived
        case resumeReceived
        case connectionLost
    }

    public enum Effect: Equatable, Sendable {
        case startBrowsing
        case stopBrowsing
        case connect(String)
        case closeConnection
        case sendHello
        case startStreaming
        case pauseStreaming
        case resumeStreaming
        case stopStreaming
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastPeer: String?

    public init(lastPeer: String? = nil) {
        self.lastPeer = lastPeer
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .start:
            guard phase == .idle else { return [] }
            phase = .searching
            return [.startBrowsing]
        case .stop:
            guard phase != .idle else { return [] }
            phase = .idle
            return [.stopStreaming, .closeConnection, .stopBrowsing]
        case let .found(names):
            return found(names)
        case .connectionReady:
            guard case let .connecting(peer) = phase else { return [] }
            phase = .handshaking(peer)
            return [.stopBrowsing, .sendHello]
        case let .helloReceived(hello):
            return helloReceived(hello)
        case .pauseReceived, .resumeReceived:
            return pauseOrResume(event)
        case .connectionLost:
            return connectionLost()
        }
    }

    private mutating func found(_ names: [String]) -> [Effect] {
        guard phase == .searching, let pick = pick(from: names) else { return [] }
        phase = .connecting(pick)
        return [.connect(pick)]
    }

    private mutating func helloReceived(_ hello: Hello) -> [Effect] {
        guard case let .handshaking(peer) = phase else { return [] }
        guard WireProtocol.supportedVersions.contains(hello.protocolVersion) else {
            phase = .incompatible(peer, peerVersion: hello.protocolVersion)
            return [.closeConnection]
        }
        phase = .live(peer)
        lastPeer = peer
        return [.startStreaming]
    }

    private mutating func pauseOrResume(_ event: Event) -> [Effect] {
        switch (event, phase) {
        case let (.pauseReceived, .live(peer)):
            phase = .paused(peer)
            return [.pauseStreaming]
        case let (.resumeReceived, .paused(peer)):
            phase = .live(peer)
            return [.resumeStreaming]
        default:
            return []
        }
    }

    private mutating func connectionLost() -> [Effect] {
        switch phase {
        case .connecting, .handshaking:
            phase = .searching
            return [.startBrowsing]
        case .live, .paused:
            phase = .searching
            return [.stopStreaming, .startBrowsing]
        case .idle, .searching, .incompatible:
            return []
        }
    }

    private func pick(from names: [String]) -> String? {
        if let lastPeer, names.contains(lastPeer) { return lastPeer }
        return names.first
    }
}
