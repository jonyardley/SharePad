@testable import SharePad
import XCTest

private struct StubValidator: KeyValidating {
    let result: Bool
    func isValid(name _: String, key _: String) -> Bool {
        result
    }
}

final class LicenseStateTests: XCTestCase {
    private let day: TimeInterval = 86400

    private func state(daysAgo: Double, name: String? = nil, key: String? = nil,
                       valid: Bool = false) -> LicenseState {
        let now = Date()
        return Licensing.state(
            firstLaunch: now.addingTimeInterval(-daysAgo * day), now: now,
            name: name, key: key, validator: StubValidator(result: valid)
        )
    }

    func testDayZeroIsFullTrial() {
        XCTAssertEqual(state(daysAgo: 0), .trial(daysRemaining: 14))
    }

    func testDay13StillTrial() {
        XCTAssertEqual(state(daysAgo: 13), .trial(daysRemaining: 1))
    }

    func testDay14Expired() {
        XCTAssertEqual(state(daysAgo: 14), .trialExpired)
    }

    func testClockSkewClampsToFullTrial() {
        XCTAssertEqual(state(daysAgo: -5), .trial(daysRemaining: 14))
    }

    func testValidKeyIsLicensedEvenPastTrial() {
        XCTAssertEqual(state(daysAgo: 99, name: "Jon", key: "k", valid: true), .licensed)
    }

    func testInvalidKeyFallsBackToTrialWindow() {
        XCTAssertEqual(state(daysAgo: 2, name: "Jon", key: "bad", valid: false),
                       .trial(daysRemaining: 12))
        XCTAssertEqual(state(daysAgo: 30, name: "Jon", key: "bad", valid: false), .trialExpired)
    }

    func testEntitlement() {
        XCTAssertTrue(LicenseState.trial(daysRemaining: 1).isEntitled)
        XCTAssertTrue(LicenseState.licensed.isEntitled)
        XCTAssertFalse(LicenseState.trialExpired.isEntitled)
    }
}
