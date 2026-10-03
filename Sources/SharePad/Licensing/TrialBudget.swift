import Foundation

// specs/wireless-product.md §10 (W4, decision 1): a source switch with the window up
// keeps the time already used, so plugging in and out cannot reset the 5 minutes.
enum TrialBudget {
    static func carried(
        _ budgets: [String: TimeInterval],
        from oldKey: String?,
        to newKey: String?,
        limit: TimeInterval
    ) -> [String: TimeInterval] {
        guard let oldKey, let newKey, oldKey != newKey,
              let left = budgets[oldKey] else { return budgets }
        var result = budgets
        result[newKey] = min(budgets[newKey] ?? limit, left)
        return result
    }
}
