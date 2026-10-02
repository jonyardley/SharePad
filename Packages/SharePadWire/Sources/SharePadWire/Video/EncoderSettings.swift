import Foundation

public struct EncoderSettings: Equatable, Sendable {
    public var averageBitRate: Int
    public var burstFactor: Double
    public var keyframeIntervalSeconds: Double

    public init(
        averageBitRate: Int = 6_000_000,
        burstFactor: Double = 1.5,
        keyframeIntervalSeconds: Double = 10
    ) {
        self.averageBitRate = averageBitRate
        self.burstFactor = burstFactor
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    public var dataRateLimits: [(bytes: Int, seconds: Double)] {
        [1, 0.1].map { seconds in
            (Int(Double(averageBitRate) * burstFactor / 8 * seconds), seconds)
        }
    }
}

public struct FrameRateEstimator: Equatable, Sendable {
    public static let window: TimeInterval = 1
    public static let changeThreshold = 0.1
    public static let applicableRates: ClosedRange<Double> = 15 ... 60

    private var captures: [TimeInterval] = []
    public private(set) var appliedRate: Double?

    public init() {}

    public var measuredRate: Double? {
        guard let first = captures.first, let last = captures.last, last > first else {
            return nil
        }
        return Double(captures.count - 1) / (last - first)
    }

    public mutating func rateToApply(afterCaptureAt now: TimeInterval) -> Double? {
        captures.append(now)
        captures.removeAll { now - $0 > Self.window }
        guard let first = captures.first, now - first >= Self.window * 0.9,
              let rate = measuredRate
        else { return nil }
        if let appliedRate, abs(rate - appliedRate) / appliedRate < Self.changeThreshold {
            return nil
        }
        let clamped = min(
            max(rate.rounded(), Self.applicableRates.lowerBound),
            Self.applicableRates.upperBound
        )
        guard clamped != appliedRate else { return nil }
        appliedRate = clamped
        return clamped
    }
}
