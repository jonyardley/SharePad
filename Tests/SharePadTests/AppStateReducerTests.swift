@testable import SharePad
import XCTest

final class AppStateReducerTests: XCTestCase {
    func testUnknownAccessChecksPermission() {
        XCTAssertEqual(state(.unknown), .checkingPermission)
    }

    func testDeniedAccess() {
        XCTAssertEqual(state(.denied, device: true, running: true), .permissionDenied)
    }

    func testGrantedNoDevice() {
        XCTAssertEqual(state(.granted), .noDevice)
    }

    func testGrantedDeviceRunningIsLive() {
        XCTAssertEqual(state(.granted, device: true, running: true), .live)
    }

    func testGrantedDeviceNotRunningIsStarting() {
        XCTAssertEqual(state(.granted, device: true), .starting)
    }

    func testGrantedDeviceFailed() {
        XCTAssertEqual(state(.granted, device: true, failed: true), .failed)
    }

    private func state(
        _ access: CameraAccess,
        device: Bool = false,
        running: Bool = false,
        failed: Bool = false
    ) -> AppState {
        AppState.reduce(access: access, hasDevice: device, isRunning: running, failed: failed)
    }
}
