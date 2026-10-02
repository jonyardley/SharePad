@testable import SharePad
import SharePadWire
import XCTest

final class PairingProgressTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")

    func testAnOfferShowsTheCodeLinkAndExpiryButNeverTheSecret() throws {
        let offer = PairingOffer.generate(at: 1000)
        var window = PairingWindow()
        _ = window.reduce(.open(offer))

        guard case let .offering(invitation) = PairingProgress(window.phase) else {
            return XCTFail("expected an offer")
        }
        XCTAssertEqual(invitation.typedCode, offer.code.typed)
        XCTAssertEqual(try XCTUnwrap(offer.code.invitationURL), invitation.link)
        XCTAssertEqual(invitation.expiresAt, Date(timeIntervalSince1970: 1300))
        XCTAssertTrue(invitation.link.absoluteString.hasPrefix("https://sharepad.co/pair#v1."))
    }

    func testEachPhaseMapsToWhatThePanelShows() {
        let offer = PairingOffer.generate(at: 0)
        var window = PairingWindow()
        XCTAssertEqual(PairingProgress(window.phase), .closed)

        _ = window.reduce(.open(offer))
        _ = window.reduce(.pairingHello(1, pad, at: 10))
        guard case let .pairing(_, iPad) = PairingProgress(window.phase) else {
            return XCTFail("expected pairing")
        }
        XCTAssertEqual(iPad, "Jon’s iPad")

        _ = window.reduce(.stored(1, pairingID: offer.pairingID, at: 20))
        XCTAssertEqual(PairingProgress(window.phase), .paired(iPad: "Jon’s iPad"))

        var expiring = PairingWindow()
        _ = expiring.reduce(.open(offer))
        _ = expiring.reduce(.tick(at: PairingOffer.lifetime))
        XCTAssertEqual(PairingProgress(expiring.phase), .expired)

        var dropped = PairingWindow()
        _ = dropped.reduce(.open(offer))
        _ = dropped.reduce(.pairingHello(1, pad, at: 10))
        _ = dropped.reduce(.connectionClosed(1))
        XCTAssertEqual(PairingProgress(dropped.phase), .interrupted)
    }
}

final class PairingPanelContentTests: XCTestCase {
    private let link = URL(string: "https://sharepad.co/pair#v1.ABCD")
    private let issued = Date(timeIntervalSince1970: 0)

    private func invitation() throws -> PairingInvitation {
        try PairingInvitation(
            typedCode: "K7QM-4XRT-9WPA-0000-1111-2222",
            link: XCTUnwrap(link),
            expiresAt: issued.addingTimeInterval(300)
        )
    }

    func testAnOpenOfferShowsTheQRCodeGroupedCodeAndCountdown() throws {
        let panel = try PairingPanelContent(
            .offering(invitation()),
            now: issued.addingTimeInterval(8)
        )
        XCTAssertEqual(panel.link, link)
        XCTAssertEqual(panel.code, "K7QM · 4XRT · 9WPA · 0000 · 1111 · 2222")
        XCTAssertEqual(panel.countdown, "Expires in 4:52")
        XCTAssertEqual(panel.status, "Waiting for your iPad…")
        XCTAssertFalse(panel.offersNewCode)
        XCTAssertFalse(panel.closesAutomatically)
    }

    func testAnOfferPastItsExpiryOffersANewCodeBeforeTheTickArrives() throws {
        let panel = try PairingPanelContent(
            .offering(invitation()),
            now: issued.addingTimeInterval(300)
        )
        XCTAssertNil(panel.link)
        XCTAssertNil(panel.code)
        XCTAssertEqual(panel.status, "This code has expired.")
        XCTAssertTrue(panel.offersNewCode)
    }

    func testPairingNamesTheIPadAndPairedClosesItself() throws {
        let pairing = try PairingPanelContent(
            .pairing(invitation(), iPad: "Jon’s iPad"),
            now: issued.addingTimeInterval(10)
        )
        XCTAssertEqual(pairing.status, "Pairing with Jon’s iPad…")

        let paired = PairingPanelContent(.paired(iPad: "Jon’s iPad"), now: issued)
        XCTAssertEqual(paired.status, "Paired with Jon’s iPad")
        XCTAssertTrue(paired.closesAutomatically)
        XCTAssertNil(paired.link)
        XCTAssertEqual(PairingPanelContent.closeDelay, .seconds(2))
    }

    func testExpiredAndInterruptedOfferANewCode() {
        XCTAssertTrue(PairingPanelContent(.expired, now: issued).offersNewCode)
        let interrupted = PairingPanelContent(.interrupted, now: issued)
        XCTAssertTrue(interrupted.offersNewCode)
        XCTAssertEqual(
            interrupted.status,
            "Pairing didn’t finish. Show a new code to try again."
        )
    }

    func testCountdownRoundsUpAndNeverGoesNegative() {
        XCTAssertEqual(PairingPanelContent.minutesAndSeconds(299.2), "5:00")
        XCTAssertEqual(PairingPanelContent.minutesAndSeconds(61), "1:01")
        XCTAssertEqual(PairingPanelContent.minutesAndSeconds(-4), "0:00")
    }

    func testTheQRCodeRenders() throws {
        let image = try XCTUnwrap(QRCode.image(for: "https://sharepad.co/pair#v1.ABCD"))
        XCTAssertGreaterThan(image.width, 100)
        XCTAssertEqual(image.width, image.height)
    }
}

final class WirelessSectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    private func iPad(
        _ name: String,
        lastConnected: Date? = nil,
        needsPairing: Bool = false
    ) -> PairedIPad {
        PairedIPad(id: UUID(), name: name, lastConnectedAt: lastConnected,
                   needsPairing: needsPairing)
    }

    func testNothingPairedShowsTheIntroAndNoToggle() {
        let section = WirelessSection(paired: [], liveIPad: nil, now: now)
        XCTAssertTrue(section.showsIntro)
        XCTAssertFalse(section.showsAllowToggle)
        XCTAssertEqual(WirelessSection.intro, "Draw on your iPad without the cable.")
    }

    func testRowsSayWhenEachIPadLastConnected() {
        let live = iPad("Studio iPad", lastConnected: now)
        let section = WirelessSection(paired: [
            iPad("Jon’s iPad", lastConnected: now.addingTimeInterval(-2 * 3600)),
            iPad("New iPad"),
            iPad("Spare iPad", lastConnected: now.addingTimeInterval(-20)),
            live,
        ], liveIPad: live.id, now: now)

        XCTAssertFalse(section.showsIntro)
        XCTAssertTrue(section.showsAllowToggle)
        XCTAssertEqual(section.rows.map(\.detail), [
            "Last connected 2 hours ago",
            "Not connected yet",
            "Last connected just now",
            "Connected now",
        ])
        XCTAssertEqual(section.rows.map(\.offersPairAgain), [false, false, false, false])
    }

    func testABrokenPairingAsksToPairAgain() {
        let section = WirelessSection(
            paired: [iPad("Jon’s iPad", lastConnected: now, needsPairing: true)],
            liveIPad: nil,
            now: now
        )
        XCTAssertEqual(section.rows.first?.detail, "Needs pairing again")
        XCTAssertEqual(section.rows.first?.offersPairAgain, true)
    }
}

@MainActor
final class AppModelPairingTests: AppModelTestCase {
    func testPairingIntentsReachTheWirelessSource() throws {
        let wireless = FakeWirelessFeed()
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: wireless
        )
        let id = UUID()

        XCTAssertTrue(model.isWirelessAvailable)
        model.pairIPad()
        model.closePairing()
        model.forgetIPad(id: id)

        XCTAssertEqual(wireless.pairingOpened, 1)
        XCTAssertEqual(wireless.pairingClosed, 1)
        XCTAssertEqual(wireless.forgotten, [id])
    }

    func testAllowWirelessIsRememberedAndPassedOn() throws {
        let wireless = FakeWirelessFeed()
        let preferences = try ephemeralPreferences()
        let model = makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: preferences,
            wireless: wireless
        )
        XCTAssertTrue(model.allowWireless)

        model.setAllowWireless(false)

        XCTAssertFalse(model.allowWireless)
        XCTAssertFalse(preferences.allowWirelessIPads)
        XCTAssertEqual(wireless.allowWireless, [false])
    }

    func testWithoutAWirelessSourceThereIsNoWirelessSection() throws {
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences()
        )
        XCTAssertFalse(model.isWirelessAvailable)
    }

    func testThePanelAndSectionReadTheLatestStatus() throws {
        let model = try makeModel(
            capture: FakeCaptureController(),
            window: FakeShareWindow(),
            preferences: ephemeralPreferences(),
            wireless: FakeWirelessFeed()
        )
        var status = WirelessStatus()
        status.pairing = .paired(iPad: "Jon’s iPad")
        status.paired = [PairedIPad(id: UUID(), name: "Jon’s iPad", lastConnectedAt: nil,
                                    needsPairing: false)]
        model.applyWireless(status)

        XCTAssertEqual(model.pairingPanel(now: Date()).status, "Paired with Jon’s iPad")
        XCTAssertEqual(model.wirelessSection(now: Date()).rows.map(\.name), ["Jon’s iPad"])
    }
}
