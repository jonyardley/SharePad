@testable import SharePadWire
import XCTest

final class EncoderSettingsTests: XCTestCase {
    func testDefaultsMatchTheSpec() {
        let settings = EncoderSettings()
        XCTAssertEqual(settings.averageBitRate, 6_000_000)
        XCTAssertEqual(settings.keyframeIntervalSeconds, 10)
        XCTAssertEqual(settings.dataRateLimits.map(\.bytes), [1_125_000, 112_500])
        XCTAssertEqual(settings.dataRateLimits.map(\.seconds), [1, 0.1])
    }

    func testFrameRateIsReportedOnceAWindowIsFull() {
        var estimator = FrameRateEstimator()
        var reported: [Double] = []
        for frame in 0 ... 60 {
            if let rate = estimator.rateToApply(afterCaptureAt: Double(frame) / 60) {
                reported.append(rate)
            }
        }
        XCTAssertEqual(reported, [60])
    }

    func testSmallDriftIsIgnoredAndALargeShiftIsReported() {
        var estimator = FrameRateEstimator()
        var time = 0.0
        for _ in 0 ... 60 {
            _ = estimator.rateToApply(afterCaptureAt: time)
            time += 1.0 / 60
        }
        var reported: [Double] = []
        for _ in 0 ..< 60 {
            if let rate = estimator.rateToApply(afterCaptureAt: time) { reported.append(rate) }
            time += 1.0 / 55
        }
        XCTAssertEqual(reported, [])
        for _ in 0 ..< 40 {
            if let rate = estimator.rateToApply(afterCaptureAt: time) { reported.append(rate) }
            time += 1.0 / 30
        }
        XCTAssertFalse(reported.isEmpty)
        XCTAssertEqual(reported.last ?? 0, 30, accuracy: 3)
    }

    func testAppliedRateIsClampedToTheDrawingRange() {
        var estimator = FrameRateEstimator()
        var reported: [Double] = []
        var time = 0.0
        for _ in 0 ... 4 {
            if let rate = estimator.rateToApply(afterCaptureAt: time) { reported.append(rate) }
            time += 0.5
        }
        XCTAssertEqual(reported, [15])
        for _ in 0 ... 240 {
            if let rate = estimator.rateToApply(afterCaptureAt: time) { reported.append(rate) }
            time += 1.0 / 120
        }
        XCTAssertEqual(reported.first, 15)
        XCTAssertEqual(reported.last, 60)
        XCTAssertTrue(reported.allSatisfy(FrameRateEstimator.applicableRates.contains))
    }
}
