@testable import SharePadWire
import XCTest

final class EncoderSettingsTests: XCTestCase {
    func testDefaultsMatchTheSpec() {
        let settings = EncoderSettings()
        XCTAssertEqual(settings.averageBitRate, 6_000_000)
        XCTAssertEqual(settings.keyframeIntervalSeconds, 10)
        XCTAssertEqual(settings.dataRateLimit.bytes, 1_125_000)
        XCTAssertEqual(settings.dataRateLimit.seconds, 1)
    }

    func testFrameRateIsReportedOnceAWindowIsFull() {
        var estimator = FrameRateEstimator()
        var reported: [Double] = []
        for frame in 0 ... 60 {
            if let rate = estimator.record(captureAt: Double(frame) / 60) {
                reported.append(rate)
            }
        }
        XCTAssertEqual(reported, [60])
    }

    func testSmallDriftIsIgnoredAndALargeShiftIsReported() {
        var estimator = FrameRateEstimator()
        var time = 0.0
        for _ in 0 ... 60 {
            _ = estimator.record(captureAt: time)
            time += 1.0 / 60
        }
        var reported: [Double] = []
        for _ in 0 ..< 60 {
            if let rate = estimator.record(captureAt: time) { reported.append(rate) }
            time += 1.0 / 55
        }
        XCTAssertEqual(reported, [])
        for _ in 0 ..< 40 {
            if let rate = estimator.record(captureAt: time) { reported.append(rate) }
            time += 1.0 / 30
        }
        XCTAssertFalse(reported.isEmpty)
        XCTAssertEqual(reported.last ?? 0, 30, accuracy: 3)
    }
}
