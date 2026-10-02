import Foundation
import Network
@testable import SharePadWire
import XCTest

final class ListenerPlanTests: XCTestCase {
    private let code = PairingCode.generate()

    private func record(lastConnected: TimeInterval? = nil) -> PairingRecord {
        PairingRecord(
            peerID: UUID(),
            peerName: "Jon’s iPad",
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1,
            lastConnectedAt: lastConnected
        )
    }

    func testNothingPairedAndNoCodeMeansNoListener() {
        XCTAssertNil(ListenerPlan.make(offering: nil, paired: [], allowWireless: true))
    }

    func testPairedIPadsKeepTheListenerOnlyWhileWirelessIsAllowed() {
        let paired = [record()]
        let allowed = ListenerPlan.make(offering: nil, paired: paired, allowWireless: true)
        XCTAssertEqual(allowed?.paired, paired)
        XCTAssertNil(allowed?.pairingCode)
        XCTAssertNil(ListenerPlan.make(offering: nil, paired: paired, allowWireless: false))
    }

    func testAnOpenPairingWindowListensEvenWithWirelessOffButAdmitsOnlyTheCode() {
        let plan = ListenerPlan.make(offering: code, paired: [record()], allowWireless: false)
        XCTAssertEqual(plan?.pairingCode, code)
        XCTAssertEqual(plan?.paired, [])
    }

    func testRecordingAConnectionTimeDoesNotChangeThePlan() {
        var paired = record()
        let before = ListenerPlan.make(offering: nil, paired: [paired], allowWireless: true)
        paired.lastConnectedAt = 99
        let after = ListenerPlan.make(offering: nil, paired: [paired], allowWireless: true)
        XCTAssertEqual(before, after)
        XCTAssertNotEqual(
            before,
            ListenerPlan.make(offering: nil, paired: [record()], allowWireless: true)
        )
        XCTAssertNotEqual(
            before,
            ListenerPlan.make(offering: code, paired: [paired], allowWireless: true)
        )
    }
}

final class PairedServicesTests: XCTestCase {
    private func record(_ peerID: UUID, pairedAt: TimeInterval,
                        lastConnected: TimeInterval? = nil) -> PairingRecord {
        PairingRecord(
            peerID: peerID,
            peerName: "Mac",
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: pairedAt,
            lastConnectedAt: lastConnected
        )
    }

    func testOnlyPairedMacsAreKeptMostRecentlyUsedFirst() {
        let home = UUID()
        let work = UUID()
        let pairings = [
            record(home, pairedAt: 10, lastConnected: 50),
            record(work, pairedAt: 20, lastConnected: 80),
        ]
        let ranked = PairedServices.rank([
            AdvertisedService(name: "Home", deviceID: home),
            AdvertisedService(name: "Stranger", deviceID: UUID()),
            AdvertisedService(name: "No id", deviceID: nil),
            AdvertisedService(name: "Work", deviceID: work),
        ], pairings: pairings)
        XCTAssertEqual(ranked.map(\.name), ["Work", "Home"])
        XCTAssertEqual(ranked.map(\.record.peerID), [work, home])
    }

    func testANeverConnectedPairingRanksByWhenItWasPaired() {
        let older = UUID()
        let newer = UUID()
        let ranked = PairedServices.rank([
            AdvertisedService(name: "Older", deviceID: older),
            AdvertisedService(name: "Newer", deviceID: newer),
        ], pairings: [record(older, pairedAt: 10), record(newer, pairedAt: 30)])
        XCTAssertEqual(ranked.map(\.name), ["Newer", "Older"])
    }

    func testTheTXTRecordCarriesTheDeviceID() {
        let id = UUID()
        XCTAssertEqual(WireService.deviceID(in: WireService.txtRecord(deviceID: id)), id)
        XCTAssertNil(WireService.deviceID(in: NWTXTRecord(["id": "not-an-id"])))
        XCTAssertNil(WireService.deviceID(in: NWTXTRecord([:])))
    }
}
