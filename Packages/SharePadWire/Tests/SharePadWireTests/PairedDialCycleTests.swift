import Foundation
@testable import SharePadWire
import XCTest

final class PairedDialCycleTests: XCTestCase {
    private let studio = pairing("Studio")
    private let office = pairing("Office")

    // ── TLS failures ──

    func testARogueWithTheMacsIDCannotPinRetriesOrCountAFailure() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue, real])
        XCTAssertEqual(dialler.dialling, "Studio")
        dialler.failTLS()
        dialler.retry()
        dialler.browse([rogue, real])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.goLive(studio)
        XCTAssertEqual(dialler.counted, [])
    }

    func testOnlyFailedServicesAdvertisedEndsTheCycleAfterOneSettle() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue, real])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([rogue])
        XCTAssertEqual(dialler.link.phase, .searching)
        XCTAssertEqual(dialler.settles.count, 1)
        XCTAssertEqual(dialler.counted, [])

        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])
        XCTAssertEqual(dialler.dialling, "Studio")
    }

    func testTheRealMacArrivingInsideTheSettleIsDialledAndNothingCounts() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue])
        dialler.failTLS()
        XCTAssertEqual(
            dialler.settles,
            [],
            "the settle clock starts on a browse, not at the failure"
        )
        dialler.retry()
        dialler.browse([rogue])
        dialler.browse([rogue, real])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.goLive(studio)
        dialler.settle()
        XCTAssertEqual(dialler.counted, [])
    }

    func testAMacIsCountedOnceEveryServiceWithItsIDHasFailed() {
        let first = service("Studio", studio)
        let second = service("Studio (2)", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([first, second])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([first, second])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.failTLS()
        dialler.retry()
        dialler.browse([first, second])
        XCTAssertEqual(dialler.counted, [])

        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])
        XCTAssertEqual(dialler.cycle.dialable, ["Studio", "Studio (2)"])
        XCTAssertEqual(dialler.dialling, "Studio")
    }

    func testALoneServiceCountsOncePerCycleSoAForgottenPairingStillBreaks() {
        let only = service("Studio", studio)
        var dialler = Dialler()
        var health = PairingHealth()

        dialler.send(.start)
        dialler.browse([only])
        for _ in 1 ... PairingHealth.failuresBeforeBroken {
            XCTAssertEqual(dialler.dialling, "Studio")
            dialler.failTLS()
            dialler.retry()
            dialler.browse([only])
            dialler.settle()
        }
        XCTAssertEqual(dialler.counted, Array(repeating: studio.peerID, count: 3))
        let marked = dialler.counted.flatMap { health.reduce(.handshakeFailed($0)) }
        XCTAssertEqual(marked, [.markBroken(studio.peerID)])
    }

    func testOneMacFailingDoesNotHideAnother() {
        var dialler = Dialler(lastPeer: "Studio")
        let services = [service("Studio", studio), service("Office", office)]

        dialler.send(.start)
        dialler.browse(services)
        XCTAssertEqual(dialler.dialling, "Studio")
        dialler.failTLS()
        dialler.retry()
        dialler.browse(services)
        XCTAssertEqual(dialler.dialling, "Office")
        dialler.goLive(office)
        XCTAssertEqual(dialler.counted, [])
    }

    func testATLSFailureOnALiveLinkIsOnlyALostConnection() {
        let only = service("Studio", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([only])
        dialler.goLive(studio)
        XCTAssertEqual(dialler.cycle.reduce(.handshakeFailed(during: dialler.link.phase)), [])
        dialler.send(.connectionLost)
        dialler.retry()
        dialler.browse([only])
        XCTAssertEqual(dialler.dialling, "Studio")
        XCTAssertEqual(dialler.settles, [])
        XCTAssertEqual(dialler.counted, [])
    }

    // ── Cycle boundaries ──

    func testEachMacWaitsForItsOwnSettle() {
        var dialler = Dialler(lastPeer: "Studio")
        let services = [service("Studio", studio), service("Office", office)]

        dialler.send(.start)
        dialler.browse(services)
        dialler.failTLS()
        dialler.retry()
        dialler.browse(services)
        XCTAssertEqual(dialler.dialling, "Office")
        dialler.failTLS()
        dialler.retry()
        dialler.browse(services)
        XCTAssertEqual(dialler.settles.count, 2)

        dialler.settle(dialler.settles[0])
        XCTAssertEqual(dialler.counted, [studio.peerID])
        XCTAssertEqual(dialler.cycle.dialable, ["Studio"])
        dialler.settle(dialler.settles[1])
        XCTAssertEqual(dialler.counted, [studio.peerID, office.peerID])
    }

    func testAFailedNameMissingFromTheBrowseIsForgottenWhenTheCycleEnds() {
        let first = service("Studio", studio)
        let second = service("Studio (2)", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([first, second])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([second])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([second])
        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])

        dialler.apply(dialler.cycle.reduce(.advertised([first, second])))
        XCTAssertEqual(dialler.cycle.dialable, ["Studio", "Studio (2)"])
    }

    func testPairingAgainForgetsAFailedNameMissingFromTheBrowse() {
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([service("Studio", studio)])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([])
        let repaired = PairingRecord(
            peerID: studio.peerID,
            peerName: "Studio",
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 20
        )
        dialler.apply(dialler.cycle.reduce(.pairingsChanged([repaired])))
        dialler.browse([service("Studio", repaired)])
        XCTAssertEqual(dialler.dialling, "Studio")
    }

    func testPairingAgainRetriesTheNewKeyOnAFailedName() {
        let only = service("Studio", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([only])
        dialler.failTLS()
        dialler.retry()
        let repaired = PairingRecord(
            peerID: studio.peerID,
            peerName: "Studio",
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 20
        )
        dialler.apply(dialler.cycle.reduce(.pairingsChanged([repaired])))
        dialler.browse([service("Studio", repaired)])
        XCTAssertEqual(dialler.dialling, "Studio")
        XCTAssertEqual(dialler.counted, [])
    }

    func testAnotherMacsPairingChangingKeepsAFailedNameSkipped() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue, real])
        dialler.failTLS()
        dialler.apply(dialler.cycle.reduce(.pairingsChanged([studio, office])))
        XCTAssertEqual(dialler.cycle.dialable, ["Studio (2)"])
    }

    func testAStaleSettleCountsNothing() {
        let only = service("Studio", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([only])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([only])
        let first = dialler.settles.last ?? 0
        dialler.send(.stop)
        dialler.settle(first)
        XCTAssertEqual(dialler.counted, [], "after stop")

        dialler.send(.start)
        dialler.browse([only])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([only])
        let second = dialler.settles.last ?? 0
        XCTAssertNotEqual(first, second)
        dialler.settle(first)
        XCTAssertEqual(dialler.counted, [], "an old token")
        dialler.settle(second)
        XCTAssertEqual(dialler.counted, [studio.peerID])

        dialler.browse([only])
        dialler.goLive(studio)
        dialler.settle(second)
        XCTAssertEqual(dialler.counted, [studio.peerID], "after live")
    }
}
