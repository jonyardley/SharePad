@testable import SharePadWire
import XCTest

final class SenderRulesTests: XCTestCase {
    private func capture(_ rules: inout SenderRules, at now: Double, inFlight: Int = 0)
        -> SenderRules.Effect? {
        rules.reduce(.frameCaptured(at: now, encodesInFlight: inFlight)).first
    }

    func testNewLinkForcesTheFirstFrameToAKeyframe() {
        var rules = SenderRules()
        _ = rules.reduce(.linkStarted)
        XCTAssertEqual(capture(&rules, at: 0), .encode(forceKeyframe: true))
        XCTAssertEqual(capture(&rules, at: 0.016), .encode(forceKeyframe: false))
    }

    func testForcedKeyframesAreAtMostOnePerHalfSecond() {
        var rules = SenderRules()
        _ = rules.reduce(.keyframeRequested)
        XCTAssertEqual(capture(&rules, at: 10), .encode(forceKeyframe: true))
        _ = rules.reduce(.keyframeRequested)
        XCTAssertEqual(capture(&rules, at: 10.2), .encode(forceKeyframe: false))
        XCTAssertEqual(capture(&rules, at: 10.49), .encode(forceKeyframe: false))
        XCTAssertEqual(capture(&rules, at: 10.5), .encode(forceKeyframe: true))
    }

    func testANaturalKeyframeSatisfiesAPendingRequest() {
        var rules = SenderRules()
        _ = rules.reduce(.keyframeRequested)
        _ = rules.reduce(.keyframeEncoded)
        XCTAssertEqual(capture(&rules, at: 1), .encode(forceKeyframe: false))
    }

    func testPauseSkipsAndResumeForcesAKeyframe() {
        var rules = SenderRules()
        _ = rules.reduce(.paused)
        XCTAssertEqual(capture(&rules, at: 1), .skip(.paused))
        _ = rules.reduce(.resumed)
        XCTAssertEqual(capture(&rules, at: 2), .encode(forceKeyframe: true))
    }

    func testEncoderBackpressureSkips() {
        var rules = SenderRules()
        XCTAssertEqual(capture(&rules, at: 1, inFlight: 3), .skip(.encoderBusy))
        XCTAssertEqual(capture(&rules, at: 1.1, inFlight: 2), .encode(forceKeyframe: false))
    }

    func testAQueueYoungerThanTheCapKeepsEncoding() {
        var rules = SenderRules()
        _ = rules.reduce(.frameHandedOff(id: 1, at: 1.0))
        XCTAssertEqual(capture(&rules, at: 1.15), .encode(forceKeyframe: false))
        XCTAssertFalse(rules.isDraining)
    }

    func testAStalledQueueStopsEncodingUntilDrainedThenSendsAKeyframe() {
        var rules = SenderRules()
        _ = rules.reduce(.frameHandedOff(id: 1, at: 1.0))
        _ = rules.reduce(.frameHandedOff(id: 2, at: 1.02))
        XCTAssertEqual(capture(&rules, at: 1.16), .skip(.draining))
        XCTAssertTrue(rules.isDraining)

        _ = rules.reduce(.frameSent(id: 1))
        XCTAssertEqual(capture(&rules, at: 1.2), .skip(.draining))

        _ = rules.reduce(.frameSent(id: 2))
        XCTAssertFalse(rules.isDraining)
        XCTAssertEqual(capture(&rules, at: 1.25), .encode(forceKeyframe: true))
    }

    func testLinkStartedClearsAStall() {
        var rules = SenderRules()
        _ = rules.reduce(.frameHandedOff(id: 1, at: 0))
        XCTAssertEqual(capture(&rules, at: 1), .skip(.draining))
        _ = rules.reduce(.linkStarted)
        XCTAssertEqual(rules.unsentFrames, 0)
        XCTAssertEqual(capture(&rules, at: 2), .encode(forceKeyframe: true))
    }
}
