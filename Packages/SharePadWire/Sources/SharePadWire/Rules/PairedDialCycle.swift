import Foundation

// The TXT id is public in mDNS, so a rogue can claim a paired Mac's id (#229): a TLS
// failure counts only once every service with that id has failed in this cycle.
public struct PairedDialCycle: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case advertised([PairedService])
        case handshakeFailed(PairedService)
        case linkUp
        case reset
    }

    public enum Effect: Equatable, Sendable {
        case countFailure(UUID)
    }

    private var advertised: [PairedService] = []
    private var failed: Set<String> = []

    public init() {}

    public var dialable: [String] {
        advertised.map(\.name).filter { !failed.contains($0) }
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .advertised(services):
            advertised = services
            return []
        case let .handshakeFailed(service):
            return handshakeFailed(service)
        case .linkUp, .reset:
            failed = []
            return []
        }
    }

    private mutating func handshakeFailed(_ service: PairedService) -> [Effect] {
        failed.insert(service.name)
        let macID = service.record.peerID
        let sameMac = advertised.filter { $0.record.peerID == macID }.map(\.name)
        guard sameMac.allSatisfy(failed.contains) else { return [] }
        failed.subtract(sameMac + [service.name])
        return [.countFailure(macID)]
    }
}
