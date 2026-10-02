import Foundation

public struct SenderRules: Equatable, Sendable {
    public static let maximumQueueAge: TimeInterval = 0.150
    public static let minimumForcedKeyframeGap: TimeInterval = 0.5
    // The first VTCompressionSession takes ~1.8 s to create; without this cap the
    // backlog drains as a burst of stale frames.
    public static let maximumEncodesInFlight = 3

    public enum Event: Equatable, Sendable {
        case linkStarted
        case keyframeRequested
        case paused
        case resumed
        case frameCaptured(at: TimeInterval, encodesInFlight: Int)
        case keyframeEncoded
        case frameHandedOff(id: UInt64, at: TimeInterval)
        case frameSent(id: UInt64)
    }

    public enum SkipReason: Equatable, Sendable {
        case paused
        case draining
        case encoderBusy
    }

    public enum Effect: Equatable, Sendable {
        case encode(forceKeyframe: Bool)
        case skip(SkipReason)
    }

    private struct Unsent: Equatable {
        let id: UInt64
        let handedOffAt: TimeInterval
    }

    public private(set) var isPaused = false
    public private(set) var isDraining = false
    public private(set) var keyframePending = false
    private var lastForcedAt: TimeInterval?
    private var unsent: [Unsent] = []

    public init() {}

    public var unsentFrames: Int {
        unsent.count
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .linkStarted:
            self = SenderRules()
            keyframePending = true
        case .keyframeRequested:
            keyframePending = true
        case .paused:
            isPaused = true
        case .resumed:
            isPaused = false
            keyframePending = true
        case let .frameCaptured(now, encodesInFlight):
            return [frameCaptured(at: now, encodesInFlight: encodesInFlight)]
        case .keyframeEncoded:
            keyframePending = false
        case let .frameHandedOff(id, now):
            unsent.append(Unsent(id: id, handedOffAt: now))
        case let .frameSent(id):
            unsent.removeAll { $0.id == id }
            if isDraining, unsent.isEmpty {
                isDraining = false
                keyframePending = true
            }
        }
        return []
    }

    private mutating func frameCaptured(at now: TimeInterval, encodesInFlight: Int) -> Effect {
        if isPaused { return .skip(.paused) }
        if let oldest = unsent.first, now - oldest.handedOffAt > Self.maximumQueueAge {
            isDraining = true
        }
        if isDraining { return .skip(.draining) }
        if encodesInFlight >= Self.maximumEncodesInFlight { return .skip(.encoderBusy) }

        let gapElapsed = lastForcedAt.map { now - $0 >= Self.minimumForcedKeyframeGap } ?? true
        guard keyframePending, gapElapsed else { return .encode(forceKeyframe: false) }
        keyframePending = false
        lastForcedAt = now
        return .encode(forceKeyframe: true)
    }
}
