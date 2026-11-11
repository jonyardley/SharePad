import Foundation

// The TXT id is public in mDNS, so a rogue can claim a paired Mac's id: a TLS failure
// counts only once every service with that id has been tried in this cycle
// (specs/wireless-pairing-ui.md, key decision 8).
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
    private var browsing = false
    private var outcomes: [String: Outcome] = [:]
    private var settleToken = 0
    private var settles: [UUID: Int] = [:]

    public init() {}

    public var dialable: [String] {
        advertised.map(\.name).filter { outcomes[$0] == nil }
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .advertised(services):
            guard browsing else { return [] }
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
            dropUnadvertised()
            return []
        case let .settleElapsed(token):
            guard let macID = settles.first(where: { $0.value == token })?.key else { return [] }
            settles[macID] = nil
            guard stalledMacs.contains(macID), let effect = endCycle(for: macID) else { return [] }
            return [effect]
        }
    }

    private mutating func linkMoved(was: SenderLink.Phase, now: SenderLink.Phase) {
        guard was != now else { return }
        browsing = now.browsing
        if !browsing { settles = [:] }
        switch now {
        case .idle, .live:
            outcomes = [:]
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
        let stalled = stalledMacs
        settles = settles.filter { stalled.contains($0.key) }
        var effects: [Effect] = []
        for macID in stalled where settles[macID] == nil {
            settleToken += 1
            settles[macID] = settleToken
            effects.append(.scheduleSettle(settleToken, after: Self.settleDelay))
        }
        return effects
    }

    private mutating func endCycle(for macID: UUID) -> Effect? {
        let counts = failedTLS(macID)
        for name in names(of: macID) {
            outcomes[name] = nil
        }
        settles[macID] = nil
        dropUnadvertised()
        return counts ? .countFailure(macID) : nil
    }

    private mutating func dropUnadvertised() {
        let names = Set(advertised.map(\.name))
        outcomes = outcomes.filter { names.contains($0.key) }
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
