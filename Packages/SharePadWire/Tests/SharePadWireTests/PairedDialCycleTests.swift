import Foundation
@testable import SharePadWire
import XCTest

private func pairing(_ name: String, peerID: UUID = UUID()) -> PairingRecord {
    PairingRecord(
        peerID: peerID,
        peerName: name,
        pairingID: UUID(),
        secret: .generate(),
        pairedAt: 10
    )
}

private struct Dialler {
    var link: SenderLink
    var cycle = PairedDialCycle()
    var counted: [UUID] = []
    var settles: [Int] = []
    var attempt = 0

    init(lastPeer: String? = nil) {
        link = SenderLink(lastPeer: lastPeer)
    }

    var dialling: String? {
        link.phase.dialling
    }

    @discardableResult
    mutating func send(_ event: SenderLink.Event) -> [SenderLink.Effect] {
        let before = link.phase
        let effects = link.reduce(event)
        apply(cycle.reduce(.linkMoved(was: before, now: link.phase)))
        for case let .scheduleConnectTimeout(attempt, _) in effects {
            self.attempt = attempt
        }
        return effects
    }

    mutating func apply(_ effects: [PairedDialCycle.Effect]) {
        for effect in effects {
            switch effect {
            case let .countFailure(macID):
                counted.append(macID)
            case let .scheduleSettle(token, after):
                XCTAssertEqual(after, SenderLink.connectTimeout)
                settles.append(token)
            }
        }
    }

    mutating func browse(_ services: [PairedService]) {
        apply(cycle.reduce(.advertised(services)))
        send(.found(cycle.dialable))
    }

    mutating func failTLS() {
        apply(cycle.reduce(.handshakeFailed(during: link.phase)))
        send(.connectionLost)
    }

    mutating func refuse() {
        send(.connectionLost)
    }

    mutating func timeOut() {
        send(.connectTimedOut(attempt: attempt))
    }

    mutating func retry() {
        send(.retryElapsed)
    }

    mutating func settle(_ token: Int? = nil) {
        guard let token = token ?? settles.last else { return XCTFail("no settle scheduled") }
        apply(cycle.reduce(.settleElapsed(token)))
        send(.found(cycle.dialable))
    }

    mutating func goLive(_ peer: PairingRecord) {
        send(.connectionReady)
        send(.helloReceived(Hello(deviceID: peer.peerID, deviceName: peer.peerName)))
    }
}

final class PairedDialCycleTests: XCTestCase {
    private let studio = pairing("Studio")
    private let office = pairing("Office")

    private func service(_ name: String, _ record: PairingRecord) -> PairedService {
        PairedService(name: name, record: record)
    }

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

    // ── Services that never answer ──

    func testAStallingRogueHoldingTheLastNameCannotPinRetries() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue, real])
        dialler.timeOut()
        dialler.retry()
        dialler.browse([rogue])
        XCTAssertNil(dialler.dialling, "a rogue-only first batch must not hand the dial back")
        dialler.browse([rogue, real])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.goLive(studio)
        dialler.settle()
        XCTAssertEqual(dialler.counted, [])
    }

    func testARefusingRogueHoldingTheLastNameCannotPinRetries() {
        let rogue = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([rogue, real])
        dialler.refuse()
        dialler.retry()
        dialler.browse([rogue, real])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        XCTAssertEqual(dialler.counted, [])
    }

    func testAnUnreachableServiceDoesNotStopAForgottenPairingCounting() {
        let stale = service("Studio", studio)
        let real = service("Studio (2)", studio)
        var dialler = Dialler(lastPeer: "Studio")

        dialler.send(.start)
        dialler.browse([stale, real])
        dialler.timeOut()
        dialler.retry()
        dialler.browse([stale, real])
        XCTAssertEqual(dialler.dialling, "Studio (2)")
        dialler.failTLS()
        dialler.retry()
        dialler.browse([stale, real])
        dialler.settle()
        XCTAssertEqual(dialler.counted, [studio.peerID])
        XCTAssertEqual(dialler.dialling, "Studio")
    }

    func testALoneUnreachableServiceIsRedialledAtOnceWithoutCounting() {
        let only = service("Studio", studio)
        var dialler = Dialler()

        dialler.send(.start)
        dialler.browse([only])
        dialler.timeOut()
        dialler.retry()
        dialler.browse([only])
        XCTAssertEqual(dialler.dialling, "Studio")
        XCTAssertEqual(dialler.settles, [])
        XCTAssertEqual(dialler.counted, [])
    }

    // ── Cycle boundaries ──

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
