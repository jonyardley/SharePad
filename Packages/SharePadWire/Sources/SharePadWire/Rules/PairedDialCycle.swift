import Foundation

// The TXT id is public in mDNS, so a rogue can claim a paired Mac's id (#229): a TLS
// failure counts only once every service with that id has been tried in this cycle.
public struct PairedDialCycle: Equatable, Sendable {
    public static let settleDelay = SenderLink.connectTimeout

    public enum Event: Equatable, Sendable {
        case advertised([PairedService])
        case handshakeFailed(during: SenderLink.Phase)
        case linkMoved(was: SenderLink.Phase, now: SenderLink.Phase)
        case pairingsChanged([PairingRecord])
        case settleElapsed(Int)
    }

    public enum Effect: Equatable, Sendable {
        case countFailure(UUID)
        case scheduleSettle(Int, after: TimeInterval)
    }

    private enum Outcome: Equatable, Sendable {
        case unreachable
        case failedTLS
    }

    private var advertised: [PairedService] = []
    private var outcomes: [String: Outcome] = [:]
    private var settleToken = 0
    private var settlePending = false

    public init() {}

    public var dialable: [String] {
        advertised.map(\.name).filter { outcomes[$0] == nil }
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .advertised(services):
            advertised = services
            return scheduleSettleIfStalled()
        case let .handshakeFailed(phase):
            if let name = phase.dialling { outcomes[name] = .failedTLS }
            return []
        case let .linkMoved(was, now):
            linkMoved(was: was, now: now)
            return []
        case let .pairingsChanged(records):
            let kept = Set(records.map(\.pairingID))
            for service in advertised where !kept.contains(service.record.pairingID) {
                outcomes[service.name] = nil
            }
            return []
        case let .settleElapsed(token):
            guard settlePending, token == settleToken else { return [] }
            settlePending = false
            return stalledMacs.compactMap { endCycle(for: $0) }
        }
    }

    private mutating func linkMoved(was: SenderLink.Phase, now: SenderLink.Phase) {
        guard was != now else { return }
        switch now {
        case .idle, .live:
            outcomes = [:]
            settlePending = false
        case .backingOff:
            guard let name = was.dialling else { return }
            if outcomes[name] == nil { outcomes[name] = .unreachable }
            if let macID = macID(of: name), stalledMacs.contains(macID), !failedTLS(macID) {
                _ = endCycle(for: macID)
            }
        default:
            break
        }
    }

    private mutating func scheduleSettleIfStalled() -> [Effect] {
        guard !settlePending, !stalledMacs.isEmpty else { return [] }
        settleToken += 1
        settlePending = true
        return [.scheduleSettle(settleToken, after: Self.settleDelay)]
    }

    private mutating func endCycle(for macID: UUID) -> Effect? {
        let counts = failedTLS(macID)
        for name in names(of: macID) {
            outcomes[name] = nil
        }
        return counts ? .countFailure(macID) : nil
    }

    private var stalledMacs: [UUID] {
        var seen = Set<UUID>()
        return advertised.map(\.record.peerID).filter { macID in
            seen.insert(macID).inserted && names(of: macID).allSatisfy { outcomes[$0] != nil }
        }
    }

    private func names(of macID: UUID) -> [String] {
        advertised.filter { $0.record.peerID == macID }.map(\.name)
    }

    private func macID(of name: String) -> UUID? {
        advertised.first { $0.name == name }?.record.peerID
    }

    private func failedTLS(_ macID: UUID) -> Bool {
        names(of: macID).contains { outcomes[$0] == .failedTLS }
    }
}
