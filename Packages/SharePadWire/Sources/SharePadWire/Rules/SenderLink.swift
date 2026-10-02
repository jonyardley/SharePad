import Foundation

public struct SenderLink: Equatable, Sendable {
    public static let connectTimeout: TimeInterval = 5
    public static let retryDelays: ClosedRange<TimeInterval> = 0.5 ... 5

    public enum Phase: Equatable, Sendable {
        case idle
        case searching
        case connecting(String)
        case handshaking(String)
        case live(String)
        case paused(String)
        case backingOff
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
        case connectTimedOut(attempt: Int)
        case retryElapsed
    }

    public enum Effect: Equatable, Sendable {
        case startBrowsing
        case stopBrowsing
        case connect(String)
        case scheduleConnectTimeout(attempt: Int, after: TimeInterval)
        case closeConnection
        case sendHello
        case startStreaming
        case pauseStreaming
        case resumeStreaming
        case stopStreaming
        case scheduleRetry(after: TimeInterval)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastPeer: String?
    public private(set) var retryDelay = Self.retryDelays.lowerBound
    private var attempt = 0

    public init(lastPeer: String? = nil) {
        self.lastPeer = lastPeer
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .start, .retryElapsed:
            startSearching(after: event)
        case .stop:
            stop()
        case let .found(names):
            found(names)
        case .connectionReady:
            connectionReady()
        case let .helloReceived(hello):
            helloReceived(hello)
        case .pauseReceived, .resumeReceived:
            pauseOrResume(event)
        case .connectionLost:
            connectionLost()
        case let .connectTimedOut(timedOut):
            connectTimedOut(attempt: timedOut)
        }
    }

    private mutating func startSearching(after event: Event) -> [Effect] {
        switch (event, phase) {
        case (.start, .idle), (.retryElapsed, .backingOff):
            phase = .searching
            return [.startBrowsing]
        default:
            return []
        }
    }

    private mutating func stop() -> [Effect] {
        guard phase != .idle else { return [] }
        phase = .idle
        retryDelay = Self.retryDelays.lowerBound
        return [.stopStreaming, .closeConnection, .stopBrowsing]
    }

    private mutating func found(_ names: [String]) -> [Effect] {
        guard phase == .searching, let pick = pick(from: names) else { return [] }
        phase = .connecting(pick)
        attempt += 1
        return [
            .connect(pick),
            .scheduleConnectTimeout(attempt: attempt, after: Self.connectTimeout),
        ]
    }

    private mutating func connectionReady() -> [Effect] {
        guard case let .connecting(peer) = phase else { return [] }
        phase = .handshaking(peer)
        return [.stopBrowsing, .sendHello]
    }

    private mutating func helloReceived(_ hello: Hello) -> [Effect] {
        guard case let .handshaking(peer) = phase else { return [] }
        guard WireProtocol.supportedVersions.contains(hello.protocolVersion) else {
            phase = .incompatible(peer, peerVersion: hello.protocolVersion)
            return [.closeConnection]
        }
        phase = .live(peer)
        lastPeer = peer
        retryDelay = Self.retryDelays.lowerBound
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
            backOff()
        case .live, .paused:
            [.stopStreaming] + backOff()
        case .idle, .searching, .backingOff, .incompatible:
            []
        }
    }

    private mutating func connectTimedOut(attempt timedOut: Int) -> [Effect] {
        guard timedOut == attempt else { return [] }
        switch phase {
        case .connecting, .handshaking:
            return [.closeConnection] + backOff()
        default:
            return []
        }
    }

    private mutating func backOff() -> [Effect] {
        phase = .backingOff
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.retryDelays.upperBound)
        return [.stopBrowsing, .scheduleRetry(after: delay)]
    }

    private func pick(from names: [String]) -> String? {
        if let lastPeer, names.contains(lastPeer) { return lastPeer }
        return names.first
    }
}
