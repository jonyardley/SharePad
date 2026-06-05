import Foundation

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed

    var isEntitled: Bool {
        switch self {
        case .trial, .licensed: true
        case .trialExpired: false
        }
    }
}

protocol KeyValidating {
    func isValid(name: String, key: String) -> Bool
}

enum Licensing {
    static let trialDays = 14

    /// Pure, so it's unit-testable without a real key or hardware (DESIGN.md §11).
    static func state(firstLaunch: Date, now: Date,
                      name: String?, key: String?,
                      validator: KeyValidating) -> LicenseState {
        if let name, let key, validator.isValid(name: name, key: key) {
            return .licensed
        }
        let elapsed = max(0, Int(now.timeIntervalSince(firstLaunch) / 86400))
        let remaining = trialDays - elapsed
        return remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }
}
