@testable import SharePad
import XCTest

final class WirelessHostTests: XCTestCase {
    private let live = SourceInput(available: true, running: true, failed: false)
    private let starting = SourceInput(available: true, running: false, failed: false)
    private let failed = SourceInput(available: true, running: false, failed: true)

    func testAHostedWirelessFeedIsActive() {
        XCTAssertTrue(active(hosted: .wireless, usb: live))
    }

    func testACableHostingTheWindowPausesWireless() {
        XCTAssertFalse(active(hosted: .usb, usb: live))
        XCTAssertFalse(active(hosted: .usb, usb: starting))
    }

    func testNoCableLeavesWirelessActiveBeforeItIsHosted() {
        XCTAssertTrue(active(hosted: .usb, usb: .absent))
    }

    func testAFailedCableLeavesWirelessActive() {
        XCTAssertTrue(active(hosted: .usb, usb: failed))
    }

    func testACableWithoutCameraAccessLeavesWirelessActive() {
        XCTAssertTrue(active(hosted: .usb, camera: .denied, usb: live))
    }

    func testTheTrialOverlayPausesWireless() {
        XCTAssertFalse(active(hosted: .wireless, usb: .absent, overlay: true))
        XCTAssertFalse(active(hosted: .usb, usb: .absent, overlay: true))
    }

    private func active(
        hosted: FeedKind,
        camera: CameraAccess = .granted,
        usb: SourceInput,
        overlay: Bool = false
    ) -> Bool {
        AppState.isWirelessHostActive(
            hosted: hosted,
            camera: camera,
            usb: usb,
            trialOverlayShown: overlay
        )
    }
}
