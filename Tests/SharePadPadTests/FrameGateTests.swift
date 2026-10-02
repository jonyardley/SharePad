@testable import SharePadPad
import XCTest

final class FrameGateTests: XCTestCase {
    func testFramesFlowWithNothingOverTheCanvas() {
        XCTAssertTrue(FrameGate().allowsFrame(at: 0))
    }

    func testAnOverlayHoldsFramesUntilItHasSettled() {
        var gate = FrameGate()
        gate.overlay(.settings, shown: true, at: 1)
        XCTAssertFalse(gate.allowsFrame(at: 2))
        gate.overlay(.settings, shown: false, at: 3)
        XCTAssertFalse(gate.allowsFrame(at: 3.2))
        XCTAssertTrue(gate.allowsFrame(at: 3 + FrameGate.settle))
    }

    func testEveryOverlayMustCloseBeforeFramesResume() {
        var gate = FrameGate()
        gate.overlay(.settings, shown: true, at: 0)
        gate.overlay(.paperMenu, shown: true, at: 0)
        gate.overlay(.paperMenu, shown: false, at: 1)
        XCTAssertFalse(gate.allowsFrame(at: 5))
    }

    func testHidingAnOverlayThatWasNeverShownDoesNotHold() {
        var gate = FrameGate()
        gate.overlay(.paperMenu, shown: false, at: 1)
        XCTAssertTrue(gate.allowsFrame(at: 1))
    }

    func testATimedHoldBlocksUntilItEnds() {
        var gate = FrameGate()
        gate.hold(for: FrameGate.recrop, at: 10)
        XCTAssertFalse(gate.allowsFrame(at: 10.5))
        XCTAssertTrue(gate.allowsFrame(at: 10 + FrameGate.recrop))
    }

    func testUnlocatedToolsHoldFramesUntilFound() {
        var gate = FrameGate()
        gate.overlay(.unlocatedTools, shown: true, at: 0)
        XCTAssertFalse(gate.allowsFrame(at: 60))
        gate.overlay(.unlocatedTools, shown: false, at: 60)
        XCTAssertTrue(gate.allowsFrame(at: 60 + FrameGate.settle))
    }
}
