import Foundation
@testable import SharePadWire
import XCTest

final class PairedDialCycleTests: XCTestCase {
    private let studio = PairingRecord(
        peerID: UUID(),
        peerName: "Studio",
        pairingID: UUID(),
        secret: .generate(),
        pairedAt: 10
    )
    private let office = PairingRecord(
        peerID: UUID(),
        peerName: "Office",
        pairingID: UUID(),
        secret: .generate(),
        pairedAt: 20
    )

    private func service(_ name: String, _ record: PairingRecord) -> PairedService {
        PairedService(name: name, record: record)
    }

    private func retry(
        _ link: inout SenderLink,
        _ cycle: inout PairedDialCycle,
        seeing batches: [PairedService]...
    ) -> [SenderLink.Effect] {
        _ = link.reduce(.connectionLost)
        _ = link.reduce(.retryElapsed)
        var effects: [SenderLink.Effect] = []
        for batch in batches {
            _ = cycle.reduce(.advertised(batch))
            effects += link.reduce(.found(cycle.dialable))
        }
        return effects
    }

    func testARogueWithTheMacsIDCannotPinRetriesOrCountAFailure() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var link = SenderLink(lastPeer: "Studio")
        var cycle = PairedDialCycle()

        _ = link.reduce(.start)
        _ = cycle.reduce(.advertised([rogue, real]))
        XCTAssertEqual(link.reduce(.found(cycle.dialable)).first, .connect("Studio"))
        XCTAssertEqual(cycle.reduce(.handshakeFailed(rogue)), [])

        let effects = retry(&link, &cycle, seeing: [rogue], [rogue, real])
        XCTAssertEqual(effects.first, .connect("Studio (2)"))
        XCTAssertEqual(link.phase, .connecting("Studio (2)"))
    }

    func testAPartialBrowseOfOnlyFailedServicesWaitsWithoutCounting() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var link = SenderLink(lastPeer: "Studio")
        var cycle = PairedDialCycle()

        _ = link.reduce(.start)
        _ = cycle.reduce(.advertised([rogue, real]))
        _ = link.reduce(.found(cycle.dialable))
        _ = cycle.reduce(.handshakeFailed(rogue))

        XCTAssertEqual(retry(&link, &cycle, seeing: [rogue]), [])
        XCTAssertEqual(link.phase, .searching)
    }

    func testAMacIsCountedOnceEveryServiceWithItsIDHasFailed() {
        let first = service("Studio", studio)
        let second = service("Studio (2)", studio)
        var link = SenderLink()
        var cycle = PairedDialCycle()

        _ = link.reduce(.start)
        _ = cycle.reduce(.advertised([first, second]))
        _ = link.reduce(.found(cycle.dialable))
        XCTAssertEqual(cycle.reduce(.handshakeFailed(first)), [])

        XCTAssertEqual(retry(&link, &cycle, seeing: [first, second]).first, .connect("Studio (2)"))
        XCTAssertEqual(cycle.reduce(.handshakeFailed(second)), [.countFailure(studio.peerID)])

        XCTAssertEqual(retry(&link, &cycle, seeing: [first, second]).first, .connect("Studio"))
        XCTAssertEqual(cycle.reduce(.handshakeFailed(first)), [])
    }

    func testALoneServiceCountsEveryFailureSoAForgottenPairingStillBreaks() {
        let only = service("Studio", studio)
        var link = SenderLink()
        var cycle = PairedDialCycle()
        var health = PairingHealth()
        var marked: [PairingHealth.Effect] = []

        _ = link.reduce(.start)
        _ = cycle.reduce(.advertised([only]))
        XCTAssertEqual(link.reduce(.found(cycle.dialable)).first, .connect("Studio"))
        for round in 1 ... PairingHealth.failuresBeforeBroken {
            let counted = cycle.reduce(.handshakeFailed(only))
            XCTAssertEqual(counted, [.countFailure(studio.peerID)], "round \(round)")
            marked += counted.flatMap { effect -> [PairingHealth.Effect] in
                guard case let .countFailure(id) = effect else { return [] }
                return health.reduce(.handshakeFailed(id))
            }
            if round < PairingHealth.failuresBeforeBroken {
                XCTAssertEqual(retry(&link, &cycle, seeing: [only]).first, .connect("Studio"))
            }
        }
        XCTAssertEqual(marked, [.markBroken(studio.peerID)])
    }

    func testOneMacFailingDoesNotHideAnother() {
        let failing = service("Studio", studio)
        let other = service("Office", office)
        var cycle = PairedDialCycle()

        _ = cycle.reduce(.advertised([failing, other]))
        XCTAssertEqual(cycle.reduce(.handshakeFailed(failing)), [.countFailure(studio.peerID)])
        XCTAssertEqual(cycle.dialable, ["Studio", "Office"])
    }

    func testGoingLiveOrResettingStartsANewCycle() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var cycle = PairedDialCycle()

        _ = cycle.reduce(.advertised([rogue, real]))
        _ = cycle.reduce(.handshakeFailed(rogue))
        XCTAssertEqual(cycle.dialable, ["Studio (2)"])
        _ = cycle.reduce(.linkUp)
        XCTAssertEqual(cycle.dialable, ["Studio", "Studio (2)"])

        _ = cycle.reduce(.handshakeFailed(rogue))
        _ = cycle.reduce(.reset)
        XCTAssertEqual(cycle.dialable, ["Studio", "Studio (2)"])
    }
}
