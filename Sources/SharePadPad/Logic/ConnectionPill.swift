import SharePadWire

enum LinkStatus: Equatable, Sendable {
    case idle
    case looking(String?)
    case live(String)
    case paused(String)
    case incompatible(String)
    case notPaired

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
        case let .paused(mac):
            self = .paused(mac)
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
        localNetworkDenied: Bool,
        captureDeclined: Bool,
        toolsFloating: Bool = false
    ) {
        if link == .notPaired {
            self.init(text: "Not paired", tone: .attention)
        } else if localNetworkDenied {
            self.init(text: "Local network is off", tone: .attention, action: .openSettings)
        } else if captureDeclined, link.isUp {
            self.init(
                text: "Screen recording did not start",
                tone: .attention,
                action: .retryCapture
            )
        } else if toolsFloating, link.isUp {
            self.init(text: "Dock the tools to keep sharing", tone: .attention)
        } else {
            self.init(link: link)
        }
    }

    private init(link: LinkStatus) {
        switch link {
        case let .live(mac):
            self.init(text: "Live on \(mac)", tone: .live)
        case .paused:
            self.init(text: "Paused on your Mac", tone: .waiting)
        case let .incompatible(mac):
            self.init(text: "Update SharePad here and on \(mac)", tone: .attention)
        case let .looking(mac?):
            self.init(text: "Looking for \(mac)…", tone: .waiting)
        case .looking(nil), .idle, .notPaired:
            self.init(text: "Looking for your Mac…", tone: .waiting)
        }
    }
}
