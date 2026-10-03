import Foundation

struct AppVersion: Comparable {
    let components: [Int]

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy { ("0" ... "9").contains($0) } ? Int(part) : nil
        }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
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

    // Bug-fix releases never go here.
    #if DEBUG
        static let featureReleases = ["1.3.0"]
    #else
        // HACK(#192): empty while wireless is Debug only, so a Release without it never
        // announces it.
        static let featureReleases: [String] = []
    #endif

    static func decide(
        lastSeen: String?,
        isFreshInstall: Bool,
        current: String,
        featureReleases: [String]
    ) -> Decision {
        guard let currentVersion = AppVersion(current) else { return .leave }
        if lastSeen == nil, isFreshInstall { return .recordSilently }
        let seen = lastSeen.flatMap(AppVersion.init)
        if lastSeen != nil, seen == nil { return .recordSilently }
        // A downgrade keeps the newer record, so going back up never re-shows it.
        if let seen, currentVersion <= seen { return .leave }
        let isNews = featureReleases.compactMap(AppVersion.init).contains { release in
            // An install from before `lastSeenVersion` existed has no record, so every
            // feature release up to this one is news to it.
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
