@testable import SharePad
import SharePadWire
import XCTest

final class WirelessHostTests: XCTestCase {
    private let live = SourceInput(available: true, running: true, failed: false)
    private let starting = SourceInput(available: true, running: false, failed: false)
    private let failed = SourceInput(available: true, running: false, failed: true)

    func testAHostedWirelessFeedIsActive() {
        XCTAssertNil(pause(hosted: .wireless, usb: live))
    }

    func testACableHostingTheWindowPausesWireless() {
        XCTAssertEqual(pause(hosted: .usb, usb: live), .cable)
        XCTAssertEqual(pause(hosted: .usb, usb: starting), .cable)
    }

    func testNoCableLeavesWirelessActiveBeforeItIsHosted() {
        XCTAssertNil(pause(hosted: .usb, usb: .absent))
    }

    func testAFailedCableLeavesWirelessActive() {
        XCTAssertNil(pause(hosted: .usb, usb: failed))
    }

    func testACableWithoutCameraAccessLeavesWirelessActive() {
        XCTAssertNil(pause(hosted: .usb, camera: .denied, usb: live))
    }

    func testTheTrialOverlayPausesWireless() {
        XCTAssertEqual(pause(hosted: .wireless, usb: .absent, overlay: true), .trial)
        XCTAssertEqual(pause(hosted: .usb, usb: .absent, overlay: true), .trial)
    }

    func testTheCableOutranksTheTrialOverlay() {
        XCTAssertEqual(pause(hosted: .usb, usb: live, overlay: true), .cable)
    }

    private func pause(
        hosted: FeedKind,
        camera: CameraAccess = .granted,
        usb: SourceInput,
        overlay: Bool = false
    ) -> PauseReason? {
        AppState.wirelessPause(
            hosted: hosted,
            camera: camera,
            usb: usb,
            trialOverlayShown: overlay
        )
    }
}
