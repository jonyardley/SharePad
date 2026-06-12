import Foundation

enum Entitlement: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed
}

enum EntitlementClock {
    static let trialDays = 7

    static func entitlement(firstLaunch: Date, now: Date, isLicensed: Bool) -> Entitlement {
        if isLicensed { return .licensed }
        // Spec §5: a clock set backwards never restarts the trial.
        guard now >= firstLaunch else { return .trialExpired }
        let day: TimeInterval = 86400
        let remaining = firstLaunch
            .addingTimeInterval(TimeInterval(trialDays) * day)
            .timeIntervalSince(now)
        guard remaining > 0 else { return .trialExpired }
        return .trial(daysLeft: Int((remaining / day).rounded(.up)))
    }
}
