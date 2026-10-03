import Foundation

struct PairingPanelContent: Equatable {
    static let closeDelay: Duration = .seconds(2)

    let link: URL?
    let code: String?
    let countdown: String?
    let status: String
    let offersNewCode: Bool
    let closesAutomatically: Bool

    var isConfirmation: Bool {
        closesAutomatically
    }

    init(_ progress: PairingProgress, now: Date) {
        switch progress {
        case let .offering(invitation) where now < invitation.expiresAt:
            self.init(invitation, now: now, status: "Waiting for your iPad…")
        case let .pairing(invitation, iPad):
            self.init(invitation, now: now, status: "Pairing with \(iPad)…")
        case let .paired(iPad):
            self.init(status: "Paired with \(iPad)", closesAutomatically: true)
        case .offering, .expired:
            self.init(status: "This code has expired.", offersNewCode: true)
        case .interrupted, .closed:
            self.init(status: "Pairing didn’t finish. Click Show New Code to try again.",
                      offersNewCode: true)
        }
    }

    private init(_ invitation: PairingInvitation, now: Date, status: String) {
        link = invitation.link
        code = invitation.typedCode.replacingOccurrences(of: "-", with: " · ")
        countdown = "Expires in " + Self
            .minutesAndSeconds(invitation.expiresAt.timeIntervalSince(now))
        self.status = status
        offersNewCode = false
        closesAutomatically = false
    }

    private init(status: String, offersNewCode: Bool = false, closesAutomatically: Bool = false) {
        link = nil
        code = nil
        countdown = nil
        self.status = status
        self.offersNewCode = offersNewCode
        self.closesAutomatically = closesAutomatically
    }

    static func minutesAndSeconds(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct WirelessSection: Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let name: String
        let detail: String
        let offersPairAgain: Bool
    }

    static let intro = "Draw on your iPad without the cable."

    let rows: [Row]

    var showsIntro: Bool {
        rows.isEmpty
    }

    var showsAllowToggle: Bool {
        !rows.isEmpty
    }

    init(paired: [PairedIPad], liveIPad: UUID?, now: Date) {
        rows = paired.map { iPad in
            Row(
                id: iPad.id,
                name: iPad.name,
                detail: Self.detail(for: iPad, isLive: iPad.id == liveIPad, now: now),
                offersPairAgain: iPad.needsPairing
            )
        }
    }

    private static func detail(for iPad: PairedIPad, isLive: Bool, now: Date) -> String {
        if iPad.needsPairing { return "Needs pairing again" }
        if isLive { return "Connected now" }
        guard let last = iPad.lastConnectedAt else { return "Not connected yet" }
        if now.timeIntervalSince(last) < 60 { return "Last connected just now" }
        return "Last connected " + relative().localizedString(for: last, relativeTo: now)
    }

    private static func relative() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.unitsStyle = .full
        return formatter
    }
}

enum PairingCodeDisplay: Equatable {
    case waiting
    case live(URL)
    case pairing(iPad: String)
    case paired(iPad: String)
    case expired

    static let mintGrace: TimeInterval = 3

    // `.closed` is both "the new code is on its way" and "another window closed the
    // offer"; only the first is worth a spinner.
    init(_ progress: PairingProgress, at now: Date, requestedAt: Date?) {
        switch progress {
        case .closed:
            let minting = requestedAt.map { now < $0 + Self.mintGrace } ?? false
            self = minting ? .waiting : .expired
        case let .offering(invitation):
            self = now >= invitation.expiresAt ? .expired : .live(invitation.link)
        case let .pairing(_, iPad):
            self = .pairing(iPad: iPad)
        case let .paired(iPad):
            self = .paired(iPad: iPad)
        case .expired, .interrupted:
            self = .expired
        }
    }

    var hasLiveCode: Bool {
        switch self {
        case .live, .pairing: true
        case .waiting, .paired, .expired: false
        }
    }

    var isPaired: Bool {
        if case .paired = self { return true }
        return false
    }
}
