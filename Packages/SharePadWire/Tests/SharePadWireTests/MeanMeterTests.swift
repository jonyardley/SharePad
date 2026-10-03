@testable import SharePadWire
import XCTest

final class MeanMeterTests: XCTestCase {
    func testAnEmptyMeterReadsZero() {
        var meter = MeanMeter()
        XCTAssertEqual(meter.takeMean(), 0)
    }

    func testTakingTheMeanStartsAFreshWindow() {
        var meter = MeanMeter()
        meter.record(2)
        meter.record(4)
        XCTAssertEqual(meter.takeMean(), 3)
        meter.record(10)
        XCTAssertEqual(meter.takeMean(), 10)
    }
}
