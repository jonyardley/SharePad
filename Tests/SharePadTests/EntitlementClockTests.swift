@testable import SharePad
import XCTest

final class EntitlementClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let day = EntitlementClock.day

    func testLicensedOverridesEverything() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 100 * day, isLicensed: true
        )
        XCTAssertEqual(result, .licensed)
    }

    func testFreshInstallHasSevenDays() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 7))
    }

    func testMidTrialCountsDown() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 2.5 * day, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 5))
    }

    func testLastSecondStillTrial() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 7 * day - 1, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 1))
    }

    func testExactlySevenDaysIsExpired() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 7 * day, isLicensed: false
        )
        XCTAssertEqual(result, .trialExpired)
    }

    func testClockRolledBackIsExpiredNotRestarted() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start - 1, isLicensed: false
        )
        XCTAssertEqual(result, .trialExpired)
    }

    func testLicensedOverridesActiveTrial() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 1 * day, isLicensed: true
        )
        XCTAssertEqual(result, .licensed)
    }
}
