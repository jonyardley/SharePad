@testable import SharePadPad
import XCTest

final class StreamingRulesTests: XCTestCase {
    private func liveAndCapturing() -> StreamingRules {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        _ = rules.reduce(.captureStarted)
        return rules
    }

    func testForegroundStartsTheLinkButNotCapture() {
        var rules = StreamingRules()
        XCTAssertEqual(rules.reduce(.scene(.active)), [.startLink])
        XCTAssertEqual(rules.capture, .idle)
    }

    func testFindingTheMacInTheForegroundStartsCapture() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        XCTAssertEqual(rules.reduce(.linkUp(true)), [.startCapture])
        XCTAssertEqual(rules.capture, .starting)
        XCTAssertEqual(rules.reduce(.captureStarted), [])
        XCTAssertEqual(rules.capture, .running)
    }

    func testBackgroundingStopsLinkAndCapture() {
        var rules = liveAndCapturing()
        XCTAssertEqual(rules.reduce(.scene(.background)), [.stopLink, .stopCapture])
        XCTAssertEqual(rules.capture, .stopping)
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        XCTAssertEqual(rules.capture, .idle)
    }

    func testInactiveChangesNothing() {
        var rules = liveAndCapturing()
        XCTAssertEqual(rules.reduce(.scene(.inactive)), [])
        XCTAssertEqual(rules.capture, .running)
        XCTAssertTrue(rules.isLinkRunning)
    }

    func testReturningToForegroundRestartsTheLink() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.scene(.background))
        _ = rules.reduce(.captureStopped)
        XCTAssertEqual(rules.reduce(.scene(.active)), [.startLink])
        XCTAssertEqual(rules.reduce(.linkUp(true)), [.startCapture])
    }

    func testLinkStatusIgnoredWhileTheLinkIsStopped() {
        var rules = StreamingRules()
        XCTAssertEqual(rules.reduce(.linkUp(true)), [])
        XCTAssertEqual(rules.capture, .idle)
    }

    func testLosingTheLinkHoldsCaptureThenStops() {
        var rules = liveAndCapturing()
        XCTAssertEqual(rules.reduce(.linkUp(false)), [.scheduleHold(1, after: 10)])
        XCTAssertEqual(rules.capture, .running)
        XCTAssertEqual(rules.reduce(.holdElapsed(1)), [.stopCapture])
    }

    func testReconnectingWithinTheHoldKeepsCapture() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.linkUp(false))
        XCTAssertEqual(rules.reduce(.linkUp(true)), [])
        XCTAssertEqual(rules.reduce(.holdElapsed(1)), [])
        XCTAssertEqual(rules.capture, .running)
    }

    func testRepeatedLinkDownDoesNotStackHolds() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.linkUp(false))
        XCTAssertEqual(rules.reduce(.linkUp(false)), [])
    }

    func testDeclinedCaptureIsNotRetriedUntilAsked() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        XCTAssertEqual(rules.reduce(.captureFailed), [])
        XCTAssertTrue(rules.captureDeclined)
        XCTAssertEqual(rules.reduce(.linkUp(true)), [])
        XCTAssertEqual(rules.reduce(.retryCapture), [.startCapture])
        XCTAssertFalse(rules.captureDeclined)
    }

    func testBackgroundingClearsADecline() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        _ = rules.reduce(.captureFailed)
        _ = rules.reduce(.scene(.background))
        XCTAssertFalse(rules.captureDeclined)
        _ = rules.reduce(.scene(.active))
        XCTAssertEqual(rules.reduce(.linkUp(true)), [.startCapture])
    }

    func testBackgroundingWhileCaptureStartsStopsItOnceStarted() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        XCTAssertEqual(rules.reduce(.scene(.background)), [.stopLink, .stopCapture])
        XCTAssertEqual(rules.reduce(.captureStarted), [.stopCapture])
    }

    func testCaptureEndedBySystemRestartsWhileWanted() {
        var rules = liveAndCapturing()
        XCTAssertEqual(rules.reduce(.captureStopped), [.startCapture])
    }

    func testStartLandingAfterTheStopCompletedStopsAgain() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        _ = rules.reduce(.scene(.background))
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        XCTAssertEqual(rules.reduce(.captureStarted), [.stopCapture])
        XCTAssertEqual(rules.capture, .stopping)
    }

    func testStaleStopWhileStartingIsIgnored() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        XCTAssertEqual(rules.capture, .starting)
    }

    func testRecordingEndedBySystemStopsWithoutRestarting() {
        var rules = liveAndCapturing()
        XCTAssertEqual(rules.reduce(.captureEnded), [.stopCapture])
        XCTAssertEqual(rules.capture, .stopping)
        XCTAssertTrue(rules.captureInterrupted)
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        XCTAssertEqual(rules.capture, .idle)
        XCTAssertTrue(rules.captureInterrupted)
        XCTAssertEqual(rules.reduce(.linkUp(true)), [])
        XCTAssertEqual(rules.reduce(.scene(.active)), [])
    }

    func testRecordingEndedWhileStartingStopsALateStart() {
        var rules = StreamingRules()
        _ = rules.reduce(.scene(.active))
        _ = rules.reduce(.linkUp(true))
        XCTAssertEqual(rules.reduce(.captureEnded), [.stopCapture])
        XCTAssertEqual(rules.capture, .stopping)
        XCTAssertTrue(rules.captureInterrupted)
        XCTAssertEqual(rules.reduce(.captureStarted), [.stopCapture])
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        XCTAssertEqual(rules.capture, .idle)
        XCTAssertTrue(rules.captureInterrupted)
    }

    func testRecordingEndedIsIgnoredWhileStoppingOrIdle() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.scene(.background))
        XCTAssertEqual(rules.reduce(.captureEnded), [])
        XCTAssertEqual(rules.capture, .stopping)
        XCTAssertFalse(rules.captureInterrupted)
        _ = rules.reduce(.captureStopped)
        XCTAssertEqual(rules.reduce(.captureEnded), [])
        XCTAssertEqual(rules.capture, .idle)
        XCTAssertFalse(rules.captureInterrupted)
    }

    func testRetryAfterRecordingEndedStartsAgain() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.captureEnded)
        _ = rules.reduce(.captureStopped)
        XCTAssertEqual(rules.reduce(.retryCapture), [.startCapture])
        XCTAssertFalse(rules.captureInterrupted)
        XCTAssertEqual(rules.capture, .starting)
    }

    func testRetryWhileTheEndedRecordingStopsStartsOnceStopped() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.captureEnded)
        XCTAssertEqual(rules.reduce(.retryCapture), [])
        XCTAssertFalse(rules.captureInterrupted)
        XCTAssertEqual(rules.reduce(.captureStopped), [.startCapture])
        XCTAssertEqual(rules.capture, .starting)
    }

    func testBackgroundingClearsAnEndedRecording() {
        var rules = liveAndCapturing()
        _ = rules.reduce(.captureEnded)
        XCTAssertEqual(rules.reduce(.scene(.background)), [.stopLink])
        XCTAssertFalse(rules.captureInterrupted)
        XCTAssertEqual(rules.reduce(.captureStopped), [])
        _ = rules.reduce(.scene(.active))
        XCTAssertEqual(rules.reduce(.linkUp(true)), [.startCapture])
    }
}
