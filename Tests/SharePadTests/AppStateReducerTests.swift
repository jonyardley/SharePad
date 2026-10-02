@testable import SharePad
import XCTest

final class AppStateReducerTests: XCTestCase {
    func testUnknownAccessChecksPermission() {
        XCTAssertEqual(state(.unknown), .checkingPermission)
    }

    func testDeniedAccess() {
        XCTAssertEqual(state(.denied, device: true, running: true), .permissionDenied)
    }

    func testRestrictedAccessIsDistinctFromDenied() {
        XCTAssertEqual(state(.restricted, device: true, running: true), .permissionRestricted)
    }

    func testGrantedNoDevice() {
        XCTAssertEqual(state(.granted), .noDevice)
    }

    func testGrantedDeviceRunningIsLive() {
        XCTAssertEqual(state(.granted, device: true, running: true), .live(.usb))
    }

    func testGrantedDeviceNotRunningIsStarting() {
        XCTAssertEqual(state(.granted, device: true), .starting(.usb))
    }

    func testGrantedDeviceFailed() {
        XCTAssertEqual(state(.granted, device: true, failed: true), .failed(.usb))
    }

    private func state(
        _ access: CameraAccess,
        device: Bool = false,
        running: Bool = false,
        failed: Bool = false
    ) -> AppState {
        AppState.reduce(
            camera: access,
            usb: SourceInput(available: device, running: running, failed: failed),
            wireless: .absent,
            localNetwork: .notRequested,
            preferred: nil
        )
    }
}

final class WirelessStateReducerTests: XCTestCase {
    private let streaming = SourceInput(available: true, running: true, failed: false)
    private let connecting = SourceInput(available: true, running: false, failed: false)
    private let plugged = SourceInput(available: true, running: true, failed: false)

    func testWirelessLiveWithCameraDeniedIsLive() {
        XCTAssertEqual(state(camera: .denied, wireless: streaming), .live(.wireless))
    }

    func testWirelessLiveBeforeCameraAnswerIsLive() {
        XCTAssertEqual(state(camera: .unknown, wireless: streaming), .live(.wireless))
    }

    func testWirelessConnectedButNoFrameYetIsStarting() {
        XCTAssertEqual(state(wireless: connecting), .starting(.wireless))
    }

    func testWirelessFailedIsFailedWireless() {
        let failed = SourceInput(available: true, running: false, failed: true)
        XCTAssertEqual(state(wireless: failed), .failed(.wireless))
    }

    func testCableWinsWithoutAPreference() {
        XCTAssertEqual(state(usb: plugged, wireless: streaming), .live(.usb))
    }

    func testPreferredWirelessWinsOverCable() {
        XCTAssertEqual(
            state(usb: plugged, wireless: streaming, preferred: .wireless),
            .live(.wireless)
        )
    }

    func testPreferredWirelessFallsBackToCableWhenAbsent() {
        XCTAssertEqual(state(usb: plugged, preferred: .wireless), .live(.usb))
    }

    func testPreferredCableFallsBackToWirelessWhenCameraDenied() {
        XCTAssertEqual(
            state(camera: .denied, usb: plugged, wireless: streaming, preferred: .usb),
            .live(.wireless)
        )
    }

    func testPluggedInWithCameraDeniedUsesWireless() {
        XCTAssertEqual(
            state(camera: .denied, usb: plugged, wireless: connecting),
            .starting(.wireless)
        )
    }

    func testFailedCableGivesWayToWireless() {
        let failedCable = SourceInput(available: true, running: false, failed: true)
        XCTAssertEqual(state(usb: failedCable, wireless: streaming), .live(.wireless))
    }

    func testLocalNetworkDeniedWithNothingConnected() {
        XCTAssertEqual(state(localNetwork: .denied), .localNetworkDenied)
    }

    func testLocalNetworkDeniedDoesNotHideALiveCable() {
        XCTAssertEqual(state(usb: plugged, localNetwork: .denied), .live(.usb))
    }

    func testCameraDeniedOutranksLocalNetworkDenied() {
        XCTAssertEqual(state(camera: .denied, localNetwork: .denied), .permissionDenied)
    }

    func testCameraUnknownOutranksLocalNetworkDenied() {
        XCTAssertEqual(state(camera: .unknown, localNetwork: .denied), .checkingPermission)
    }

    func testLocalNetworkGrantedWithNothingConnectedIsNoDevice() {
        XCTAssertEqual(state(localNetwork: .granted), .noDevice)
    }

    func testActiveFeedIsReadFromTheState() {
        XCTAssertEqual(AppState.live(.wireless).activeFeed, .wireless)
        XCTAssertEqual(AppState.starting(.usb).activeFeed, .usb)
        XCTAssertNil(AppState.localNetworkDenied.activeFeed)
    }

    private func state(
        camera: CameraAccess = .granted,
        usb: SourceInput = .absent,
        wireless: SourceInput = .absent,
        localNetwork: LocalNetworkAccess = .notRequested,
        preferred: FeedKind? = nil
    ) -> AppState {
        AppState.reduce(
            camera: camera,
            usb: usb,
            wireless: wireless,
            localNetwork: localNetwork,
            preferred: preferred
        )
    }
}
