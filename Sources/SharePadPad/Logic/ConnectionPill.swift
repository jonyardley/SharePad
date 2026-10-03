import SharePadWire

enum LinkStatus: Equatable, Sendable {
    case idle
    case looking(String?)
    case live(String)
    case paused(String, PauseReason)
    case incompatible(String)

    init(_ phase: SenderLink.Phase, lastMac: String?) {
        switch phase {
        case .idle:
            self = .idle
        case .searching, .backingOff:
            self = .looking(lastMac)
        case let .connecting(mac), let .handshaking(mac):
            self = .looking(mac)
        case let .live(mac):
            self = .live(mac)
        case let .paused(mac, reason):
            self = .paused(mac, reason)
        case let .incompatible(mac, _):
            self = .incompatible(mac)
        }
    }

    var isUp: Bool {
        switch self {
        case .live, .paused: true
        default: false
        }
    }

    var liveMac: String? {
        if case let .live(mac) = self { return mac }
        return nil
    }
}

struct ConnectionPill: Equatable {
    enum Tone: Equatable {
        case live
        case waiting
        case attention
    }

    enum Action: Equatable {
        case openSettings
        case retryCapture
        case pair
        case pairAgain
    }

    let text: String
    let tone: Tone
    let action: Action?

    init(text: String, tone: Tone, action: Action? = nil) {
        self.text = text
        self.tone = tone
        self.action = action
    }

    init(
        link: LinkStatus,
        pairing: PairingState = .paired,
        localNetworkDenied: Bool,
        captureDeclined: Bool,
        toolsUnlocated: Bool = false
    ) {
        if pairing == .unpaired {
            self.init(text: "Not paired with a Mac", tone: .attention, action: .pair)
        } else if localNetworkDenied {
            self.init(text: "Local network is off", tone: .attention, action: .openSettings)
        } else if captureDeclined, link.isUp {
            self.init(
                text: "Screen recording not allowed",
                tone: .attention,
                action: .retryCapture
            )
        } else if toolsUnlocated, link.isUp {
            self.init(text: "Sharing paused. Hide the tools to resume.", tone: .attention)
        } else if case let .broken(mac) = pairing, !link.isUp {
            self.init(text: "Not paired with \(mac)", tone: .attention, action: .pairAgain)
        } else {
            self.init(link: link)
        }
    }

    private init(link: LinkStatus) {
        switch link {
        case let .live(mac):
            self.init(text: "Live on \(mac)", tone: .live)
        case let .paused(mac, .cable):
            self.init(text: "Sharing over the cable to \(mac)", tone: .waiting)
        case let .paused(mac, _):
            self.init(text: "Paused on \(mac)", tone: .waiting)
        case let .incompatible(mac):
            self.init(text: "Update SharePad here and on \(mac)", tone: .attention)
        case let .looking(mac?):
            self.init(text: "Looking for \(mac)…", tone: .waiting)
        case .looking(nil), .idle:
            self.init(text: "Looking for your Mac…", tone: .waiting)
        }
    }
}
