import Foundation
@testable import SharePadWire
import XCTest

final class PairedDialCycleBrowsingTests: XCTestCase {
    private let studio = pairing("Studio")
    private let office = pairing("Office")

    private func studioStalledWhileOfficeIsDialled() -> Dialler {
        var dialler = Dialler(lastPeer: "Studio")
        let services = [service("Studio", studio), service("Office", office)]
        dialler.send(.start)
        dialler.browse(services)
        dialler.failTLS()
        dialler.retry()
        dialler.browse(services)
        XCTAssertEqual(dialler.dialling, "Office")
        XCTAssertEqual(dialler.settles.count, 1)
        return dialler
    }

    func testASettleDueDuringBackoffCountsNothingAndTheRealMacIsDialled() {
        var dialler = studioStalledWhileOfficeIsDialled()
        let armed = dialler.settles[0]

        dialler.failTLS()
        dialler.settle(armed)
        XCTAssertEqual(dialler.link.phase, .backingOff)
        XCTAssertEqual(dialler.counted, [])

        dialler.retry()
        dialler.browse([
            service("Studio", studio),
            service("Studio (2)", studio),
            service("Office", office),
        ])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.goLive(studio)
        XCTAssertEqual(dialler.counted, [])
    }

    func testASettleDueDuringBackoffWaitsAFullSettleOnTheNextBrowse() {
        var dialler = studioStalledWhileOfficeIsDialled()
        let armed = dialler.settles[0]

        dialler.failTLS()
        dialler.settle(armed)
        dialler.retry()
        dialler.browse([service("Studio", studio), service("Office", office)])
        XCTAssertEqual(dialler.settles.count, 3, "a fresh settle for each stalled Mac")
        XCTAssertEqual(dialler.counted, [])

        dialler.settle(dialler.settles[1])
        XCTAssertEqual(dialler.counted, [studio.peerID])
    }

    func testAPairingChangeDuringBackoffStartsNoSettle() {
        var dialler = Dialler(lastPeer: "Studio")
        let services = [service("Studio", studio), service("Office", office)]

        dialler.send(.start)
        dialler.browse(services)
        dialler.failTLS()
        dialler.pairingsChanged([studio, office, pairing("Lounge")])
        XCTAssertEqual(dialler.settles, [], "the browser is stopped during backoff")

        dialler.retry()
        dialler.browse([service("Studio", studio)])
        XCTAssertEqual(dialler.settles.count, 1)
        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])
    }

    func testAnotherMacTimingOutStillLetsAFailedMacCount() {
        var dialler = studioStalledWhileOfficeIsDialled()

        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])
        dialler.timeOut()
        XCTAssertEqual(dialler.link.phase, .backingOff)
    }

    func testATimingOutMacSeenFirstHoldsOffACountForAsLongAsItComesFirst() {
        var dialler = Dialler(lastPeer: "Studio")
        let both = [service("Office", office), service("Studio", studio)]

        dialler.send(.start)
        dialler.browse([service("Studio", studio)])
        dialler.failTLS()
        for _ in 1 ... 3 {
            dialler.retry()
            dialler.browse([service("Office", office)])
            XCTAssertEqual(dialler.dialling, "Office")
            dialler.browse(both)
            let armed = dialler.settles.last
            dialler.timeOut()
            if let armed { dialler.settle(armed) }
        }
        XCTAssertEqual(dialler.settles.count, 3, "a settle each round, each dropped by the backoff")
        XCTAssertEqual(dialler.counted, [])
    }

    func testAPairingChangeBeforeTheNewBrowseAnswersStartsNoSettle() {
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([service("Studio", studio)])
        dialler.failTLS()
        dialler.retry()
        dialler.pairingsChanged([studio, office])
        XCTAssertEqual(dialler.settles, [], "the old browser's list is gone")
    }

    func testGoingLiveOnAnotherMacDropsAPendingSettle() {
        var dialler = studioStalledWhileOfficeIsDialled()
        let stale = dialler.settles[0]

        dialler.goLive(office)
        dialler.send(.connectionLost)
        dialler.retry()
        dialler.browse([service("Studio", studio)])
        dialler.failTLS()
        dialler.retry()
        dialler.browse([service("Studio", studio), service("Office", office)])
        XCTAssertEqual(dialler.settles.count, 2, "a new settle, not the one from before live")

        dialler.settle(stale)
        XCTAssertEqual(dialler.counted, [])
        dialler.settle(dialler.settles[1])
        XCTAssertEqual(dialler.counted, [studio.peerID])
    }
}
