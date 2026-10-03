@testable import SharePad
import XCTest

final class TrialBudgetTests: XCTestCase {
    func testANewSourceInheritsWhatTheOldOneHadLeft() {
        let result = TrialBudget.carried(["cable": 70], from: "cable", to: "wireless:x", limit: 300)
        XCTAssertEqual(result["wireless:x"], 70)
        XCTAssertEqual(result["cable"], 70)
    }

    func testANewSourceKeepsItsOwnBudgetWhenThatIsSmaller() {
        let result = TrialBudget.carried(
            ["cable": 200, "wireless:x": 40], from: "cable", to: "wireless:x", limit: 300
        )
        XCTAssertEqual(result["wireless:x"], 40)
    }

    func testAnExhaustedBudgetStaysExhaustedAcrossTheSwitch() {
        let result = TrialBudget.carried(
            ["wireless:x": 0],
            from: "wireless:x",
            to: "cable",
            limit: 300
        )
        XCTAssertEqual(result["cable"], 0)
    }

    func testNothingCarriesWithoutAMeteredOldSource() {
        let budgets: [String: TimeInterval] = ["cable": 50]
        XCTAssertEqual(TrialBudget.carried(budgets, from: nil, to: "cable", limit: 300), budgets)
        XCTAssertEqual(
            TrialBudget.carried(budgets, from: "other", to: "cable", limit: 300),
            budgets
        )
        XCTAssertEqual(TrialBudget.carried(budgets, from: "cable", to: nil, limit: 300), budgets)
        XCTAssertEqual(
            TrialBudget.carried(budgets, from: "cable", to: "cable", limit: 300),
            budgets
        )
    }
}
