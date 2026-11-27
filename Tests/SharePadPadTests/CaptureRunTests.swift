@testable import SharePadPad
import XCTest

@MainActor
final class CaptureRunTests: XCTestCase {
    private var endedCount = 0

    private func makeRun() -> CaptureRun {
        CaptureRun { [weak self] in self?.endedCount += 1 }
    }

    func testStopAfterStartReportsEnded() {
        let run = makeRun()
        run.didStart(true)
        run.recordingStopped()
        XCTAssertEqual(endedCount, 1)
    }

    func testStopBeforeStartIsReportedOnceStarted() {
        let run = makeRun()
        run.recordingStopped()
        XCTAssertEqual(endedCount, 0)
        run.didStart(true)
        XCTAssertEqual(endedCount, 1)
    }

    func testStopBeforeAFailedStartIsNotReported() {
        let run = makeRun()
        run.recordingStopped()
        run.didStart(false)
        XCTAssertEqual(endedCount, 0)
    }

    func testCancelledRunNeverReportsEnded() {
        let run = makeRun()
        run.recordingStopped()
        run.cancel()
        run.didStart(true)
        run.recordingStopped()
        XCTAssertEqual(endedCount, 0)
    }

    func testEndedIsReportedOnlyOnce() {
        let run = makeRun()
        run.didStart(true)
        run.recordingStopped()
        run.recordingStopped()
        XCTAssertEqual(endedCount, 1)
    }
}
