import Foundation

struct WirelessPeer: Equatable, Sendable {
    let id: UUID
    let name: String
}

struct WirelessStatus: Equatable, Sendable {
    var peer: WirelessPeer?
    var isReceiving = false
    var isReconnecting = false
    var localNetwork: LocalNetworkAccess = .notRequested
    var listenerFailed = false

    var input: SourceInput {
        SourceInput(available: peer != nil, running: isReceiving, failed: false)
    }
}

struct SourceOption: Identifiable, Equatable {
    let id: String
    let label: String
}
