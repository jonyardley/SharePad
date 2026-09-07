import Foundation

/// NTP-style offset between the two devices' wall clocks, so a sender-stamped
/// capture time can be compared against the receiver's clock. Without this, the
/// per-frame latency figure is just the unknown clock skew between an iPad and a
/// Mac, which is routinely tens of milliseconds and sometimes seconds.
public final class ClockSync {
    /// senderClock ≈ receiverClock + offset
    public private(set) var offset: Double = 0
    public private(set) var roundTrip: Double = 0
    public private(set) var sampleCount = 0

    private var offsets: [Double] = []

    public init() {}

    public var isSynced: Bool {
        sampleCount > 0
    }

    public func handlePong(t1: Double, t2: Double, t3: Double) {
        let rtt = t3 - t1
        guard rtt >= 0, rtt < 2 else { return }
        offsets.append(t2 - (t1 + rtt / 2))
        if offsets.count > 9 { offsets.removeFirst() }
        offset = offsets.sorted()[offsets.count / 2]
        roundTrip = rtt
        sampleCount += 1
    }
}

public struct RollingStats {
    private var samples: [Double] = []
    private let capacity: Int

    public init(capacity: Int = 150) {
        self.capacity = capacity
    }

    public mutating func add(_ value: Double) {
        samples.append(value)
        if samples.count > capacity { samples.removeFirst() }
    }

    public var count: Int {
        samples.count
    }

    public var median: Double? {
        percentile(0.5)
    }

    public var p95: Double? {
        percentile(0.95)
    }

    public var lowest: Double? {
        samples.min()
    }

    public var highest: Double? {
        samples.max()
    }

    /// Median absolute deviation: jitter that a single outlier cannot dominate,
    /// which matters because the go/kill call is about consistency, not just the
    /// median (specs/wireless.md).
    public var medianAbsoluteDeviation: Double? {
        guard let median else { return nil }
        var deviations = RollingStats(capacity: capacity)
        for sample in samples {
            deviations.add(abs(sample - median))
        }
        return deviations.median
    }

    private func percentile(_ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }
}

public struct RateMeter {
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var events = 0
    private var bytes = 0

    public private(set) var eventsPerSecond: Double = 0
    public private(set) var bytesPerSecond: Double = 0

    public init() {}

    public mutating func record(bytes byteCount: Int) {
        events += 1
        bytes += byteCount
    }

    /// Returns true when a new window was published, i.e. once a second.
    public mutating func tick() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return false }
        eventsPerSecond = Double(events) / elapsed
        bytesPerSecond = Double(bytes) / elapsed
        events = 0
        bytes = 0
        windowStart = now
        return true
    }
}
