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

    // kVTCompressionPropertyKey_DataRateLimits takes [bytes, seconds] pairs.
    public var dataRateLimit: (bytes: Int, seconds: Double) {
        (Int(Double(averageBitRate) * burstFactor / 8), 1)
    }
}

public struct FrameRateEstimator: Equatable, Sendable {
    public static let window: TimeInterval = 1
    public static let changeThreshold = 0.1

    private var captures: [TimeInterval] = []
    public private(set) var appliedRate: Double?

    public init() {}

    public var measuredRate: Double? {
        guard let first = captures.first, let last = captures.last, last > first else {
            return nil
        }
        return Double(captures.count - 1) / (last - first)
    }

    // Returns a rate only when the encoder should be told about it: the first full
    // window, then any shift beyond the threshold.
    public mutating func record(captureAt now: TimeInterval) -> Double? {
        captures.append(now)
        captures.removeAll { now - $0 > Self.window }
        guard let first = captures.first, now - first >= Self.window * 0.9,
              let rate = measuredRate
        else { return nil }
        if let appliedRate, abs(rate - appliedRate) / appliedRate < Self.changeThreshold {
            return nil
        }
        let rounded = rate.rounded()
        appliedRate = rounded
        return rounded
    }
}
