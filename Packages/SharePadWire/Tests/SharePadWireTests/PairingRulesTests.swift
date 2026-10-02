import Foundation
@testable import SharePadWire
import XCTest

final class PairingWindowTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
    private let offer = PairingOffer.generate(at: 100)

    private var grant: PairingGrant {
        PairingGrant(pairingID: offer.pairingID, secret: offer.secret)
    }

    private func record(at time: TimeInterval) -> PairingRecord {
        PairingRecord(
            peerID: pad.deviceID,
            peerName: pad.deviceName,
            pairingID: offer.pairingID,
            secret: offer.secret,
            pairedAt: time
        )
    }

    private func granting(_ window: inout PairingWindow, connection: ConnectionID = 1) {
        _ = window.reduce(.open(offer))
        _ = window.reduce(.pairingHello(connection, pad, at: 150))
    }

    func testTheHappyPathGrantsThenStoresOnceTheIPadConfirms() {
        var window = PairingWindow()
        XCTAssertEqual(window.reduce(.open(offer)), [.acceptPairing(offer.code)])
        XCTAssertEqual(window.acceptingCode, offer.code)
        XCTAssertEqual(window.reduce(.pairingHello(1, pad, at: 150)), [.sendGrant(1, grant)])
        XCTAssertEqual(window.acceptingCode, offer.code)
        XCTAssertEqual(
            window.reduce(.stored(1, pairingID: offer.pairingID, at: 160)),
            [.store(record(at: 160)), .stopAcceptingPairing, .close(1, .finished)]
        )
        XCTAssertEqual(window.phase, .paired(record(at: 160)))
        XCTAssertNil(window.acceptingCode)
    }

    func testEveryOfferHasFreshSecrets() {
        let other = PairingOffer.generate(at: 100)
        XCTAssertNotEqual(other.code, offer.code)
        XCTAssertNotEqual(other.secret, offer.secret)
        XCTAssertNotEqual(other.pairingID, offer.pairingID)
    }

    func testTheCodeExpiresAfterFiveMinutes() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(window.reduce(.tick(at: 399)), [])
        XCTAssertEqual(window.reduce(.tick(at: 400)), [.stopAcceptingPairing])
        XCTAssertEqual(window.phase, .expired)
        XCTAssertNil(window.acceptingCode)
        XCTAssertEqual(window.reduce(.pairingHello(1, pad, at: 401)), [.close(1, .expired)])
    }

    func testAHelloAfterExpiryWithoutATickIsRejected() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(
            window.reduce(.pairingHello(1, pad, at: 500)),
            [.close(1, .expired), .stopAcceptingPairing]
        )
        XCTAssertEqual(window.phase, .expired)
    }

    func testExpiryMidGrantClosesTheConnection() {
        var window = PairingWindow()
        granting(&window)
        XCTAssertEqual(window.reduce(.tick(at: 400)), [.close(1, .expired), .stopAcceptingPairing])
        XCTAssertEqual(window.reduce(.stored(1, pairingID: offer.pairingID, at: 401)), [])
        XCTAssertEqual(window.phase, .expired)
    }

    func testTheCodeIsSingleUse() {
        var window = PairingWindow()
        granting(&window)
        let other = Hello(deviceID: UUID(), deviceName: "Other")
        XCTAssertEqual(window.reduce(.pairingHello(2, other, at: 151)), [.close(2, .alreadyUsed)])
        _ = window.reduce(.stored(1, pairingID: offer.pairingID, at: 160))
        XCTAssertEqual(window.reduce(.pairingHello(3, other, at: 161)), [.close(3, .alreadyUsed)])
    }

    func testARepeatedHelloOnTheGrantingConnectionChangesNothing() {
        var window = PairingWindow()
        granting(&window)
        XCTAssertEqual(window.reduce(.pairingHello(1, pad, at: 151)), [])
    }

    func testAConfirmationForAnotherPairingOrConnectionBurnsTheCode() {
        var window = PairingWindow()
        granting(&window)
        XCTAssertEqual(
            window.reduce(.stored(1, pairingID: UUID(), at: 160)),
            [.close(1, .protocolViolation), .stopAcceptingPairing]
        )
        XCTAssertEqual(window.phase, .interrupted)

        var other = PairingWindow()
        granting(&other)
        XCTAssertEqual(
            other.reduce(.stored(2, pairingID: offer.pairingID, at: 160)),
            [.close(2, .protocolViolation)]
        )
        XCTAssertEqual(other.phase, .granting(offer, connection: 1, peer: pad))
    }

    func testLosingTheConnectionMidGrantBurnsTheCode() {
        var window = PairingWindow()
        granting(&window)
        XCTAssertEqual(window.reduce(.connectionClosed(2)), [])
        XCTAssertEqual(window.reduce(.connectionClosed(1)), [.stopAcceptingPairing])
        XCTAssertEqual(window.phase, .interrupted)
        XCTAssertNil(window.acceptingCode)
        XCTAssertEqual(window.reduce(.pairingHello(2, pad, at: 170)), [.close(2, .alreadyUsed)])
    }

    func testAnIncompatibleIPadIsTurnedAwayWithoutSpendingTheCode() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        let future = Hello(protocolVersion: 99, deviceID: UUID(), deviceName: "Future")
        XCTAssertEqual(
            window.reduce(.pairingHello(1, future, at: 150)),
            [.close(1, .incompatible(peerVersion: 99))]
        )
        XCTAssertEqual(window.phase, .offering(offer))
    }

    func testHelloWithNoWindowOpenIsRejected() {
        var window = PairingWindow()
        XCTAssertEqual(window.reduce(.pairingHello(1, pad, at: 1)), [.close(1, .notOffering)])
        XCTAssertEqual(window.reduce(.stored(1, pairingID: offer.pairingID, at: 1)), [])
    }

    func testClosingTheWindowStopsAcceptingAndDropsAGrant() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(window.reduce(.close), [.stopAcceptingPairing])
        XCTAssertEqual(window.reduce(.close), [])

        var granting = PairingWindow()
        self.granting(&granting)
        XCTAssertEqual(granting.reduce(.close), [.close(1, .cancelled), .stopAcceptingPairing])
        XCTAssertEqual(granting.phase, .closed)
    }

    func testANewCodeReplacesTheOldOne() {
        var window = PairingWindow()
        granting(&window)
        let fresh = PairingOffer.generate(at: 200)
        XCTAssertEqual(
            window.reduce(.open(fresh)),
            [.close(1, .cancelled), .acceptPairing(fresh.code)]
        )
        XCTAssertEqual(window.acceptingCode, fresh.code)
    }
}

final class PadPairingTests: XCTestCase {
    private let code = PairingCode.generate()
    private let mac = Hello(deviceID: UUID(), deviceName: "Jon’s MacBook Pro")
    private let grant = PairingGrant(pairingID: UUID(), secret: .generate())

    private func started() -> PadPairing {
        var pairing = PadPairing()
        _ = pairing.reduce(.start(code))
        return pairing
    }

    func testTheHappyPath() {
        var pairing = PadPairing()
        XCTAssertEqual(
            pairing.reduce(.start(code)),
            [.startBrowsing, .scheduleTimeout(attempt: 1, after: 30)]
        )
        XCTAssertEqual(pairing.reduce(.found(["Studio"])), [.connect("Studio", code)])
        XCTAssertEqual(pairing.reduce(.connectionReady), [.sendCredentials(code)])
        XCTAssertEqual(pairing.reduce(.helloReceived(mac)), [])
        let record = PairingRecord(
            peerID: mac.deviceID,
            peerName: mac.deviceName,
            pairingID: grant.pairingID,
            secret: grant.secret,
            pairedAt: 42
        )
        XCTAssertEqual(
            pairing.reduce(.grantReceived(grant, at: 42)),
            [.save(record), .sendStored(grant.pairingID), .stopBrowsing]
        )
        XCTAssertEqual(pairing.phase, .paired(record))
        XCTAssertEqual(pairing.reduce(.connectionFailed), [])
        XCTAssertEqual(pairing.reduce(.timedOut(attempt: 1)), [])
    }

    func testAMacThatRejectsTheCodeIsSkippedForTheNextOne() {
        var pairing = started()
        _ = pairing.reduce(.found(["Someone else", "Studio"]))
        XCTAssertEqual(
            pairing.reduce(.connectionFailed),
            [.closeConnection, .connect("Studio", code)]
        )
        XCTAssertEqual(pairing.phase, .trying("Studio"))
        XCTAssertEqual(pairing.reduce(.connectionFailed), [.closeConnection])
        XCTAssertEqual(pairing.phase, .searching)
        XCTAssertEqual(pairing.reduce(.found(["Someone else", "Studio"])), [])
        XCTAssertEqual(
            pairing.reduce(.found(["Someone else", "Studio", "Office"])),
            [.connect("Office", code)]
        )
    }

    func testAGrantBeforeTheMacSaysHelloIsAProtocolError() {
        var pairing = started()
        _ = pairing.reduce(.found(["Studio"]))
        _ = pairing.reduce(.connectionReady)
        XCTAssertEqual(pairing.reduce(.grantReceived(grant, at: 1)), [.closeConnection])
        XCTAssertEqual(pairing.phase, .searching)
    }

    func testAnIncompatibleMacIsSkipped() {
        var pairing = started()
        _ = pairing.reduce(.found(["Studio"]))
        _ = pairing.reduce(.connectionReady)
        let future = Hello(protocolVersion: 99, deviceID: UUID(), deviceName: "Future")
        XCTAssertEqual(pairing.reduce(.helloReceived(future)), [.closeConnection])
        XCTAssertEqual(pairing.phase, .searching)
    }

    func testGivingUpAfterTheTimeout() {
        var pairing = started()
        _ = pairing.reduce(.found(["Studio"]))
        XCTAssertEqual(pairing.reduce(.timedOut(attempt: 1)), [.closeConnection, .stopBrowsing])
        XCTAssertEqual(pairing.phase, .failed(.noMacAccepted))
        XCTAssertEqual(pairing.reduce(.found(["Studio"])), [])
    }

    func testAStaleTimeoutFromAnEarlierAttemptIsIgnored() {
        var pairing = started()
        _ = pairing.reduce(.cancel)
        XCTAssertEqual(
            pairing.reduce(.start(code)),
            [.startBrowsing, .scheduleTimeout(attempt: 2, after: 30)]
        )
        XCTAssertEqual(pairing.reduce(.timedOut(attempt: 1)), [])
        XCTAssertEqual(pairing.phase, .searching)
    }

    func testCancelTearsDown() {
        var pairing = started()
        _ = pairing.reduce(.found(["Studio"]))
        XCTAssertEqual(pairing.reduce(.cancel), [.closeConnection, .stopBrowsing])
        XCTAssertEqual(pairing.phase, .idle)
        XCTAssertEqual(pairing.reduce(.cancel), [])
    }

    func testRetryingAfterFailureStartsClean() {
        var pairing = started()
        _ = pairing.reduce(.found(["Studio"]))
        _ = pairing.reduce(.connectionFailed)
        _ = pairing.reduce(.timedOut(attempt: 1))
        _ = pairing.reduce(.start(code))
        XCTAssertEqual(pairing.reduce(.found(["Studio"])), [.connect("Studio", code)])
    }

    func testEventsOutOfOrderAreIgnored() {
        var pairing = PadPairing()
        XCTAssertEqual(pairing.reduce(.connectionReady), [])
        XCTAssertEqual(pairing.reduce(.helloReceived(mac)), [])
        XCTAssertEqual(pairing.reduce(.grantReceived(grant, at: 1)), [])
        XCTAssertEqual(pairing.reduce(.found(["Studio"])), [])
        XCTAssertEqual(pairing.phase, .idle)
    }
}

final class PairingBookTests: XCTestCase {
    private func record(peer: UUID = UUID(), name: String = "Jon’s iPad",
                        at time: TimeInterval = 1) -> PairingRecord {
        PairingRecord(
            peerID: peer,
            peerName: name,
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: time
        )
    }

    func testLoadingReplacesTheListAndReloadsCredentials() {
        var book = PairingBook()
        let records = [record(), record()]
        XCTAssertEqual(book.reduce(.loaded(records)), [.reloadCredentials])
        XCTAssertEqual(book.records, records)
    }

    func testANewPairingIsSavedAndAdded() {
        var book = PairingBook()
        let first = record()
        XCTAssertEqual(book.reduce(.paired(first)), [.save(first), .reloadCredentials])
        XCTAssertEqual(book.records, [first])
    }

    func testRepairingReplacesTheEntryForThatDevice() {
        let peer = UUID()
        let old = record(peer: peer, name: "Old name", at: 1)
        let other = record()
        var book = PairingBook([old, other])
        let fresh = record(peer: peer, name: "New name", at: 2)
        XCTAssertEqual(
            book.reduce(.paired(fresh)),
            [.save(fresh), .dropConnections(peerID: peer), .reloadCredentials]
        )
        XCTAssertEqual(book.records, [fresh, other])
    }

    func testForgetDeletesDropsAndReloads() {
        let peer = UUID()
        var book = PairingBook([record(peer: peer)])
        XCTAssertEqual(
            book.reduce(.forget(peerID: peer)),
            [.delete(peerID: peer), .dropConnections(peerID: peer), .reloadCredentials]
        )
        XCTAssertTrue(book.records.isEmpty)
        XCTAssertEqual(book.reduce(.forget(peerID: peer)), [])
    }

    func testConnectingRecordsWhenAndPicksTheMostRecent() {
        let home = record(name: "Home")
        let office = record(name: "Office")
        var book = PairingBook([home, office])
        XCTAssertNil(book.mostRecent(among: [home.peerID, office.peerID])?.lastConnectedAt)

        var updated = office
        updated.lastConnectedAt = 50
        XCTAssertEqual(book.reduce(.connected(peerID: office.peerID, at: 50)), [.save(updated)])
        XCTAssertEqual(book.mostRecent(among: [home.peerID, office.peerID]), updated)
        _ = book.reduce(.connected(peerID: home.peerID, at: 60))
        XCTAssertEqual(book.mostRecent(among: [home.peerID, office.peerID])?.peerName, "Home")
        XCTAssertEqual(book.mostRecent(among: [office.peerID])?.peerName, "Office")
        XCTAssertNil(book.mostRecent(among: []))
        XCTAssertEqual(book.reduce(.connected(peerID: UUID(), at: 70)), [])
    }

    func testLookupByPairingID() {
        let mine = record()
        let book = PairingBook([record(), mine])
        XCTAssertEqual(book.record(pairingID: mine.pairingID), mine)
        XCTAssertNil(book.record(pairingID: UUID()))
    }
}

final class PairingHealthTests: XCTestCase {
    private let id = UUID()

    func testThreeFailedHandshakesInARowMarkAPairingBroken() {
        var health = PairingHealth()
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [.markBroken(id)])
        XCTAssertTrue(health.isBroken(id))
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeSucceeded(id)), [.markHealthy(id)])
        XCTAssertFalse(health.isBroken(id))
    }

    func testASuccessResetsTheCount() {
        var health = PairingHealth()
        _ = health.reduce(.handshakeFailed(id))
        _ = health.reduce(.handshakeFailed(id))
        XCTAssertEqual(health.reduce(.handshakeSucceeded(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertFalse(health.isBroken(id))
    }
}
