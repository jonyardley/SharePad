@testable import SharePad
import XCTest

final class SparkleUpdaterTests: XCTestCase {
    // Normal outcomes (no update, user cancelled/deferred an install) must not be
    // reported as failures. Codes are Sparkle SUErrors.h values.
    func testBenignSparkleCodesAreNotReported() {
        XCTAssertFalse(SparkleUpdater.shouldReport(abortErrorCode: 1001)) // no update
        XCTAssertFalse(SparkleUpdater.shouldReport(abortErrorCode: 4007)) // install cancelled
        XCTAssertFalse(SparkleUpdater.shouldReport(abortErrorCode: 4008)) // authorize later
    }

    func testRealFailuresAreReported() {
        XCTAssertTrue(SparkleUpdater.shouldReport(abortErrorCode: 2001)) // download error
        XCTAssertTrue(SparkleUpdater.shouldReport(abortErrorCode: 9999)) // any other failure
    }
}
