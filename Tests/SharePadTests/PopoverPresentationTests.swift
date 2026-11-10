@testable import SharePad
import XCTest

final class PopoverPresentationTests: XCTestCase {
    func testEachStateHasItsStatusLine() {
        let cases: [(AppState, StatusLine)] = [
            (.checkingPermission, .checkingPermission),
            (.permissionDenied, .cameraOff),
            (.permissionRestricted, .cameraBlocked),
            (.localNetworkDenied, .localNetworkOff),
            (.noDevice, .noIPad),
            (.starting(.usb), .connecting(.usb)),
            (.starting(.wireless), .connecting(.wireless)),
            (.live(.usb), .sharingOverCable),
            (.live(.wireless), .sharingOverWiFi),
            (.failed(.usb), .failed(.usb)),
            (.failed(.wireless), .failed(.wireless)),
        ]
        for (state, line) in cases {
            XCTAssertEqual(StatusLine(state: state, isReconnecting: false), line, "\(state)")
        }
    }

    func testAReconnectingWiFiShareSaysSo() {
        XCTAssertEqual(
            StatusLine(state: .live(.wireless), isReconnecting: true),
            .reconnectingOverWiFi
        )
    }

    func testReconnectingOnlyChangesALiveWiFiShare() {
        XCTAssertEqual(StatusLine(state: .live(.usb), isReconnecting: true), .sharingOverCable)
        XCTAssertEqual(
            StatusLine(state: .starting(.wireless), isReconnecting: true),
            .connecting(.wireless)
        )
    }

    func testAKeychainFailureOutranksAListenerFailureWithNoIPad() {
        var wireless = WirelessStatus()
        wireless.pairingStoreFailed = true
        wireless.listenerFailed = true

        XCTAssertEqual(hint(.noDevice, wireless), .pairingStoreFailed)
    }

    func testAListenerFailureShowsWithNoIPad() {
        var wireless = WirelessStatus()
        wireless.listenerFailed = true

        XCTAssertEqual(hint(.noDevice, wireless), .listenerFailed)
    }

    func testWirelessFailuresOnlyShowWithNoIPad() {
        var wireless = WirelessStatus()
        wireless.pairingStoreFailed = true
        wireless.listenerFailed = true

        XCTAssertEqual(hint(.starting(.usb), wireless), .unlockAndTrust)
        XCTAssertNil(hint(.live(.usb), wireless))
    }

    func testEachStateHasItsHint() {
        XCTAssertEqual(hint(.noDevice), .plugIn)
        XCTAssertEqual(hint(.starting(.usb)), .unlockAndTrust)
        XCTAssertEqual(hint(.failed(.usb)), .checkCable)
        XCTAssertEqual(hint(.permissionDenied), .cameraOff)
        XCTAssertEqual(hint(.permissionRestricted), .cameraBlocked)
        XCTAssertEqual(hint(.localNetworkDenied), .localNetworkOff)
        XCTAssertNil(hint(.checkingPermission))
        XCTAssertNil(hint(.starting(.wireless)))
        XCTAssertNil(hint(.live(.usb)))
        XCTAssertNil(hint(.live(.wireless)))
        XCTAssertNil(hint(.failed(.wireless)))
    }

    func testAWiFiShareWithoutCameraAccessSaysTheCableNeedsIt() {
        XCTAssertEqual(hint(.live(.wireless), cameraDenied: true), .cableNeedsCamera)
        XCTAssertNil(hint(.starting(.wireless), cameraDenied: true))
    }

    func testALicensedCopyHasNoLicenceRow() {
        XCTAssertEqual(license(.licensed), .licensed)
    }

    func testATrialShowsItsDaysLeft() {
        XCTAssertEqual(license(.trial(daysLeft: 3)), .trial(daysLeft: 3))
    }

    func testAShownOverlayOutranksTheSessionEndTime() {
        let endsAt = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(license(.trialExpired, overlayShown: true, endsAt: endsAt), .paused)
    }

    func testACountingDownSessionShowsWhenItPauses() {
        let endsAt = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(license(.trialExpired, endsAt: endsAt), .pausesAt(endsAt))
    }

    func testAnEndedTrialWithNoSessionShowsTheLimit() {
        XCTAssertEqual(license(.trialExpired), .pausesAfter(minutes: 15))
    }

    func testWhatsNewOffersPairingWhenWirelessIsAvailableAndNothingIsPaired() {
        XCTAssertEqual(
            WhatsNew.Buttons(wirelessAvailable: true, pairing: .closed),
            .pairOrNotNow
        )
        XCTAssertEqual(
            WhatsNew.Buttons(wirelessAvailable: true, pairing: .expired),
            .pairOrNotNow
        )
    }

    func testWhatsNewSaysDoneOncePaired() {
        XCTAssertEqual(
            WhatsNew.Buttons(wirelessAvailable: true, pairing: .paired(iPad: "Jon’s iPad")),
            .done
        )
    }

    func testWhatsNewSaysDoneWithoutWireless() {
        XCTAssertEqual(WhatsNew.Buttons(wirelessAvailable: false, pairing: .closed), .done)
    }

    private func hint(
        _ state: AppState,
        _ wireless: WirelessStatus = WirelessStatus(),
        cameraDenied: Bool = false
    ) -> StatusHint? {
        StatusHint(state: state, wireless: wireless, cameraDenied: cameraDenied)
    }

    private func license(
        _ entitlement: Entitlement,
        overlayShown: Bool = false,
        endsAt: Date? = nil
    ) -> LicenseStatus {
        LicenseStatus(
            entitlement: entitlement,
            overlayShown: overlayShown,
            sessionEndsAt: endsAt,
            sessionLimitMinutes: 15
        )
    }
}

@MainActor
final class AppModelPopoverTests: AppModelTestCase {
    func testTheShippedBuildOffersBuyAndRecover() throws {
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences()
        )

        XCTAssertTrue(model.canBuy)
        XCTAssertTrue(model.canRecover)
    }

    func testWhatsNewOffersPairingOnlyWithAWirelessFeed() throws {
        let cableOnly = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences()
        )
        let withWireless = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: FakeWirelessFeed()
        )

        XCTAssertEqual(cableOnly.whatsNewButtons, .done)
        XCTAssertEqual(withWireless.whatsNewButtons, .pairOrNotNow)
    }

    func testAWiFiShareWithoutCameraAccessHintsAtTheCable() throws {
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: FakeWirelessFeed(),
            permission: .denied
        )
        model.applyWireless(WirelessStatus(
            peer: WirelessPeer(id: UUID(), name: "Jon’s iPad"),
            isReceiving: true,
            isReconnecting: true
        ))

        XCTAssertEqual(model.statusLine, .reconnectingOverWiFi)
        XCTAssertEqual(model.statusHint, .cableNeedsCamera)
    }
}
