import Foundation
@testable import SharePadWire
import XCTest

final class PairedDialCycleUnreachableTests: XCTestCase {
    private let studio = pairing("Studio")

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
}
