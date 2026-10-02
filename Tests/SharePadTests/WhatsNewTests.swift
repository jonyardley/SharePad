@testable import SharePad
import XCTest

final class WhatsNewTests: XCTestCase {
    private let features = ["1.3"]

    private func decide(
        _ lastSeen: String?,
        _ current: String,
        fresh: Bool = false,
        features: [String]? = nil
    ) -> WhatsNew.Decision {
        WhatsNew.decide(
            lastSeen: lastSeen,
            isFreshInstall: fresh,
            current: current,
            featureReleases: features ?? self.features
        )
    }

    // ── Version comparison ──

    func testVersionsCompareNumericallyNotAsText() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.10")), try XCTUnwrap(AppVersion("1.9")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.2.9")), try XCTUnwrap(AppVersion("1.2.10")))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("2.0")), try XCTUnwrap(AppVersion("1.99.99")))
    }

    func testMissingTrailingComponentsCountAsZero() throws {
        XCTAssertEqual(try XCTUnwrap(AppVersion("1.3")), try XCTUnwrap(AppVersion("1.3.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.3")), try XCTUnwrap(AppVersion("1.3.1")))
    }

    func testRejectsVersionsThatAreNotDottedNumbers() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.3-beta"))
        XCTAssertNil(AppVersion("1..3"))
        XCTAssertNil(AppVersion("v1.3"))
        XCTAssertNil(AppVersion("+1.3"))
        XCTAssertNil(AppVersion("1.-3"))
        XCTAssertNil(AppVersion("1.3."))
    }

    // ── Decision ──

    func testUpdateToAFeatureReleaseShows() {
        XCTAssertEqual(decide("1.2", "1.3"), .show)
        XCTAssertEqual(decide("1.2.0", "1.3.0"), .show)
    }

    func testBugFixReleaseRecordsSilently() {
        XCTAssertEqual(decide("1.3", "1.3.1"), .recordSilently)
        XCTAssertEqual(decide("1.1", "1.2"), .recordSilently)
    }

    func testSkippingPastAFeatureReleaseStillShows() {
        XCTAssertEqual(decide("1.2", "1.3.2"), .show)
        XCTAssertEqual(decide("1.1", "1.4"), .show)
    }

    func testFeatureReleaseAlreadySeenDoesNotShowAgain() {
        XCTAssertEqual(decide("1.3", "1.3"), .leave)
        XCTAssertEqual(decide("1.3.1", "1.4"), .recordSilently)
    }

    func testFeatureReleaseNewerThanCurrentDoesNotShow() {
        XCTAssertEqual(decide("1.2", "1.4", features: ["1.5"]), .recordSilently)
    }

    func testDowngradeLeavesTheNewerRecord() {
        XCTAssertEqual(decide("1.4", "1.3"), .leave)
        XCTAssertEqual(decide("1.4", "1.2"), .leave)
    }

    func testFreshInstallRecordsSilentlyEvenOnAFeatureRelease() {
        XCTAssertEqual(decide(nil, "1.3", fresh: true), .recordSilently)
    }

    func testInstallFromBeforeTheRecordExistedShows() {
        XCTAssertEqual(decide(nil, "1.3"), .show)
        XCTAssertEqual(decide(nil, "1.2.1"), .recordSilently)
    }

    func testComparesSemanticallyAcrossTens() {
        XCTAssertEqual(decide("1.9", "1.10", features: ["1.10"]), .show)
        XCTAssertEqual(decide("1.10", "1.10.1", features: ["1.9", "1.10"]), .recordSilently)
    }

    func testEmptyFeatureListNeverShows() {
        XCTAssertEqual(decide("1.2", "1.3", features: []), .recordSilently)
        XCTAssertEqual(decide(nil, "1.3", features: []), .recordSilently)
    }

    func testUnreadableVersionsNeverShow() {
        XCTAssertEqual(decide("1.2", "1.3-beta"), .leave)
        XCTAssertEqual(decide("garbage", "1.3"), .recordSilently)
        XCTAssertEqual(decide("1.2", "1.3", features: ["next"]), .recordSilently)
    }

    func testShouldShowMatchesTheDecision() {
        XCTAssertTrue(WhatsNew.shouldShow(
            lastSeen: "1.2", isFreshInstall: false, current: "1.3", featureReleases: features
        ))
        XCTAssertFalse(WhatsNew.shouldShow(
            lastSeen: "1.3", isFreshInstall: false, current: "1.3.1", featureReleases: features
        ))
    }

    func testShippedFeatureListParses() {
        for release in WhatsNew.featureReleases {
            XCTAssertNotNil(AppVersion(release), release)
        }
    }

    // ── Pairing offer ──

    func testPairingOfferDisplay() throws {
        let url = try XCTUnwrap(URL(string: "https://sharepad.co/pair#code"))
        let offer = PairingOffer(invitationURL: url, expiresAt: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(PairingOffer.Display(nil, at: Date()), .waiting)
        XCTAssertEqual(
            PairingOffer.Display(offer, at: Date(timeIntervalSince1970: 299)),
            .live(url)
        )
        XCTAssertEqual(PairingOffer.Display(offer, at: Date(timeIntervalSince1970: 300)), .expired)
    }
}
