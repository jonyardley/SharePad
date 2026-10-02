@testable import SharePadPad
import SharePadWire
import XCTest

final class ConnectionPillTests: XCTestCase {
    private func pill(
        _ link: LinkStatus,
        denied: Bool = false,
        declined: Bool = false
    ) -> ConnectionPill {
        ConnectionPill(link: link, localNetworkDenied: denied, captureDeclined: declined)
    }

    func testLiveNamesTheMac() {
        XCTAssertEqual(pill(.live("Studio")), ConnectionPill(text: "Live on Studio", tone: .live))
    }

    func testLookingNamesTheLastMacWhenKnown() {
        XCTAssertEqual(pill(.looking("Studio")).text, "Looking for Studio…")
        XCTAssertEqual(pill(.looking(nil)).text, "Looking for your Mac…")
        XCTAssertEqual(pill(.idle).text, "Looking for your Mac…")
    }

    func testPausedOnTheMac() {
        XCTAssertEqual(pill(.paused("Studio")).text, "Paused on Studio")
    }

    func testLocalNetworkOffOffersSettings() {
        XCTAssertEqual(
            pill(.looking(nil), denied: true),
            ConnectionPill(text: "Local network is off", tone: .attention, action: .openSettings)
        )
    }

    func testDeclinedRecordingOffersARetryOnlyWhileConnected() {
        XCTAssertEqual(pill(.live("Studio"), declined: true).action, .retryCapture)
        XCTAssertNil(pill(.looking(nil), declined: true).action)
    }

    func testNotPairedWinsAndOffersPairing() {
        let unpaired = ConnectionPill(
            link: .looking(nil),
            pairing: .unpaired,
            localNetworkDenied: true,
            captureDeclined: false
        )
        XCTAssertEqual(
            unpaired,
            ConnectionPill(text: "Not paired with a Mac", tone: .attention, action: .pair)
        )
    }

    func testABrokenPairingNamesTheMacUntilALinkIsUp() {
        let broken = ConnectionPill(
            link: .looking("Studio"),
            pairing: .broken("Studio"),
            localNetworkDenied: false,
            captureDeclined: false
        )
        XCTAssertEqual(
            broken,
            ConnectionPill(text: "Not paired with Studio", tone: .attention, action: .pairAgain)
        )
        let liveElsewhere = ConnectionPill(
            link: .live("Office"),
            pairing: .broken("Studio"),
            localNetworkDenied: false,
            captureDeclined: false
        )
        XCTAssertEqual(liveElsewhere.text, "Live on Office")
    }

    func testCopyAvoidsTransportJargon() {
        let all: [LinkStatus] = [
            .idle, .looking(nil), .live("Mac"), .paused("Mac"), .incompatible("Mac"),
        ]
        for status in all {
            for text in [pill(status).text, pill(status, denied: true).text] {
                XCTAssertFalse(text.contains("LAN"), text)
                XCTAssertFalse(text.contains("Bonjour"), text)
                XCTAssertFalse(text.contains("receiver"), text)
            }
        }
    }

    func testSenderPhasesMapToStatus() {
        XCTAssertEqual(LinkStatus(.searching, lastMac: "Studio"), .looking("Studio"))
        XCTAssertEqual(LinkStatus(.backingOff, lastMac: nil), .looking(nil))
        XCTAssertEqual(LinkStatus(.connecting("Office"), lastMac: "Studio"), .looking("Office"))
        XCTAssertEqual(LinkStatus(.live("Office"), lastMac: nil), .live("Office"))
        XCTAssertEqual(
            LinkStatus(.incompatible("Office", peerVersion: 9), lastMac: nil),
            .incompatible("Office")
        )
        XCTAssertTrue(LinkStatus.paused("Office").isUp)
        XCTAssertFalse(LinkStatus.looking("Office").isUp)
    }

    func testUnlocatedToolsAskToDockWhileConnected() {
        let live = ConnectionPill(
            link: .live("Studio"),
            localNetworkDenied: false,
            captureDeclined: false,
            toolsUnlocated: true
        )
        XCTAssertEqual(live.text, "Sharing paused. Hide the tools to resume.")
        let looking = ConnectionPill(
            link: .looking(nil),
            localNetworkDenied: false,
            captureDeclined: false,
            toolsUnlocated: true
        )
        XCTAssertEqual(looking.text, "Looking for your Mac…")
    }
}
