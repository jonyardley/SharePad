import Foundation

public struct KeyframeRequester: Equatable, Sendable {
    public static let retryAfter: TimeInterval = 1

    public enum Event: Equatable, Sendable {
        case connected(at: TimeInterval)
        case decodeFailed(at: TimeInterval)
        case layerFlushed(at: TimeInterval)
        case frameArrived(isKeyframe: Bool, at: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        case sendRequest
        case decode
        case discard
    }

    public private(set) var awaitingKeyframe = false
    private var lastRequestAt: TimeInterval?

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .connected(now):
            self = KeyframeRequester()
            return request(at: now)
        case let .decodeFailed(now), let .layerFlushed(now):
            return request(at: now)
        case let .frameArrived(isKeyframe, now):
            if isKeyframe {
                awaitingKeyframe = false
                return [.decode]
            }
            guard awaitingKeyframe else { return [.decode] }
            return request(at: now) + [.discard]
        }
    }

    private mutating func request(at now: TimeInterval) -> [Effect] {
        let recentlyAsked = awaitingKeyframe
            && lastRequestAt.map { now - $0 < Self.retryAfter } == true
        awaitingKeyframe = true
        guard !recentlyAsked else { return [] }
        lastRequestAt = now
        return [.sendRequest]
    }
}
