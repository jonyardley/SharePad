import Foundation

struct AppVersion: Comparable {
    let components: [Int]

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 })
        else { return nil }
        components = numbers
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let length = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< length {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum WhatsNew {
    enum Decision: Equatable {
        case show
        case recordSilently
        case leave
    }

    // The releases whose what's-new window is worth an interruption. Bug-fix releases
    // never go here. Empty until the wireless release has a version (W5b, #170).
    static let featureReleases: [String] = []

    static func decide(
        lastSeen: String?,
        isFreshInstall: Bool,
        current: String,
        featureReleases: [String]
    ) -> Decision {
        guard let currentVersion = AppVersion(current) else { return .leave }
        if lastSeen == nil, isFreshInstall { return .recordSilently }
        // An install from before `lastSeenVersion` existed has no record, so every
        // feature release up to this one is news to it.
        let seen = lastSeen.flatMap(AppVersion.init)
        if lastSeen != nil, seen == nil { return .recordSilently }
        // A downgrade keeps the newer record, so going back up never re-shows it.
        if let seen, currentVersion <= seen { return .leave }
        let isNews = featureReleases.compactMap(AppVersion.init).contains { release in
            release <= currentVersion && seen.map { release > $0 } ?? true
        }
        return isNews ? .show : .recordSilently
    }

    static func shouldShow(
        lastSeen: String?,
        isFreshInstall: Bool,
        current: String,
        featureReleases: [String]
    ) -> Bool {
        decide(
            lastSeen: lastSeen,
            isFreshInstall: isFreshInstall,
            current: current,
            featureReleases: featureReleases
        ) == .show
    }
}
