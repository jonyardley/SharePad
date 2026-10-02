import Foundation

public struct PairingOffer: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    public let code: PairingCode
    public let pairingID: UUID
    public let secret: LinkSecret
    public let issuedAt: TimeInterval

    public init(code: PairingCode, pairingID: UUID, secret: LinkSecret, issuedAt: TimeInterval) {
        self.code = code
        self.pairingID = pairingID
        self.secret = secret
        self.issuedAt = issuedAt
    }

    public static func generate(at now: TimeInterval) -> PairingOffer {
        PairingOffer(code: .generate(), pairingID: UUID(), secret: .generate(), issuedAt: now)
    }

    public func isExpired(at now: TimeInterval) -> Bool {
        now - issuedAt >= Self.lifetime
    }

    var grant: PairingGrant {
        PairingGrant(pairingID: pairingID, secret: secret)
    }
}

public struct PairingWindow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        case offering(PairingOffer)
        case granting(PairingOffer, connection: ConnectionID, peer: Hello)
        case paired(PairingRecord)
        case expired
        case interrupted
    }

    public enum CloseReason: Equatable, Sendable {
        case notOffering
        case expired
        case alreadyUsed
        case incompatible(peerVersion: UInt16)
        case protocolViolation
        case cancelled
        case finished
    }

    public enum Event: Equatable, Sendable {
        case open(PairingOffer)
        case pairingHello(ConnectionID, Hello, at: TimeInterval)
        case stored(ConnectionID, pairingID: UUID, at: TimeInterval)
        case connectionClosed(ConnectionID)
        case tick(at: TimeInterval)
        case close
    }

    public enum Effect: Equatable, Sendable {
        case acceptPairing(PairingCode)
        case stopAcceptingPairing
        case sendGrant(ConnectionID, PairingGrant)
        case store(PairingRecord)
        case close(ConnectionID, CloseReason)
    }

    public private(set) var phase: Phase = .closed

    public init() {}

    public var acceptingCode: PairingCode? {
        switch phase {
        case let .offering(offer), let .granting(offer, _, _): offer.code
        default: nil
        }
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .open(offer):
            let dropped = dropGrant(.cancelled)
            phase = .offering(offer)
            return dropped + [.acceptPairing(offer.code)]
        case let .pairingHello(connection, peer, now):
            return pairingHello(connection, peer, at: now)
        case let .stored(connection, pairingID, now):
            return stored(connection, pairingID: pairingID, at: now)
        case let .connectionClosed(connection):
            guard case let .granting(_, current, _) = phase,
                  current == connection else { return [] }
            phase = .interrupted
            return [.stopAcceptingPairing]
        case let .tick(now):
            switch phase {
            case let .offering(offer) where offer.isExpired(at: now),
                 let .granting(offer, _, _) where offer.isExpired(at: now):
                let dropped = dropGrant(.expired)
                phase = .expired
                return dropped + [.stopAcceptingPairing]
            default:
                return []
            }
        case .close:
            let wasAccepting = acceptingCode != nil
            let dropped = dropGrant(.cancelled)
            phase = .closed
            return dropped + (wasAccepting ? [.stopAcceptingPairing] : [])
        }
    }

    private mutating func pairingHello(
        _ connection: ConnectionID,
        _ peer: Hello,
        at now: TimeInterval
    ) -> [Effect] {
        switch phase {
        case let .offering(offer):
            guard !offer.isExpired(at: now) else {
                phase = .expired
                return [.close(connection, .expired), .stopAcceptingPairing]
            }
            guard WireProtocol.supportedVersions.contains(peer.protocolVersion) else {
                return [.close(connection, .incompatible(peerVersion: peer.protocolVersion))]
            }
            phase = .granting(offer, connection: connection, peer: peer)
            return [.sendGrant(connection, offer.grant)]
        case let .granting(_, current, _) where current == connection:
            return []
        case .granting, .paired, .interrupted:
            return [.close(connection, .alreadyUsed)]
        case .expired:
            return [.close(connection, .expired)]
        case .closed:
            return [.close(connection, .notOffering)]
        }
    }

    private mutating func stored(_ connection: ConnectionID, pairingID: UUID,
                                 at now: TimeInterval) -> [Effect] {
        guard case let .granting(offer, current, peer) = phase else { return [] }
        guard connection == current else { return [.close(connection, .protocolViolation)] }
        guard pairingID == offer.pairingID else {
            phase = .interrupted
            return [.close(connection, .protocolViolation), .stopAcceptingPairing]
        }
        let record = PairingRecord(
            peerID: peer.deviceID,
            peerName: peer.deviceName,
            pairingID: offer.pairingID,
            secret: offer.secret,
            pairedAt: now
        )
        phase = .paired(record)
        return [.store(record), .stopAcceptingPairing, .close(connection, .finished)]
    }

    private func dropGrant(_ reason: CloseReason) -> [Effect] {
        guard case let .granting(_, connection, _) = phase else { return [] }
        return [.close(connection, reason)]
    }
}

public struct PadPairing: Equatable, Sendable {
    public static let timeout: TimeInterval = 30

    public enum Failure: Equatable, Sendable {
        case noMacAccepted
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case searching
        case trying(String)
        case awaitingGrant(String, mac: Hello?)
        case paired(PairingRecord)
        case failed(Failure)
    }

    public enum Event: Equatable, Sendable {
        case start(PairingCode)
        case found([String])
        case connectionReady
        case connectionFailed
        case helloReceived(Hello)
        case grantReceived(PairingGrant, at: TimeInterval)
        case timedOut(attempt: Int)
        case cancel
    }

    public enum Effect: Equatable, Sendable {
        case startBrowsing
        case stopBrowsing
        case connect(String, PairingCode)
        case sendCredentials(PairingCode)
        case save(PairingRecord)
        case sendStored(UUID)
        case closeConnection
        case scheduleTimeout(attempt: Int, after: TimeInterval)
    }

    public private(set) var phase: Phase = .idle
    private var code: PairingCode?
    private var known: [String] = []
    private var tried: Set<String> = []
    private var attempt = 0

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .start(code):
            return start(code)
        case let .found(names):
            return found(names)
        case .connectionReady:
            guard case let .trying(name) = phase, let code else { return [] }
            phase = .awaitingGrant(name, mac: nil)
            return [.sendCredentials(code)]
        case .connectionFailed:
            return failCurrent()
        case let .helloReceived(hello):
            return helloReceived(hello)
        case let .grantReceived(grant, now):
            return grantReceived(grant, at: now)
        case let .timedOut(timedOut):
            return timedOut == attempt ? giveUp() : []
        case .cancel:
            let teardown: [Effect] = isActive ? [.closeConnection, .stopBrowsing] : []
            code = nil
            phase = .idle
            return teardown
        }
    }

    private mutating func start(_ code: PairingCode) -> [Effect] {
        let teardown: [Effect] = isActive ? [.closeConnection, .stopBrowsing] : []
        self.code = code
        known = []
        tried = []
        attempt += 1
        phase = .searching
        return teardown + [.startBrowsing, .scheduleTimeout(attempt: attempt, after: Self.timeout)]
    }

    private mutating func found(_ names: [String]) -> [Effect] {
        guard isActive else { return [] }
        known = names
        return phase == .searching ? tryNext() : []
    }

    private mutating func giveUp() -> [Effect] {
        guard isActive else { return [] }
        code = nil
        phase = .failed(.noMacAccepted)
        return [.closeConnection, .stopBrowsing]
    }

    private mutating func helloReceived(_ hello: Hello) -> [Effect] {
        guard case let .awaitingGrant(name, nil) = phase else { return [] }
        guard WireProtocol.supportedVersions.contains(hello.protocolVersion)
        else { return failCurrent() }
        phase = .awaitingGrant(name, mac: hello)
        return []
    }

    private var isActive: Bool {
        switch phase {
        case .searching, .trying, .awaitingGrant: true
        case .idle, .paired, .failed: false
        }
    }

    private mutating func tryNext() -> [Effect] {
        guard let code, let next = known.first(where: { !tried.contains($0) }) else {
            phase = .searching
            return []
        }
        phase = .trying(next)
        return [.connect(next, code)]
    }

    private mutating func failCurrent() -> [Effect] {
        switch phase {
        case let .trying(name), let .awaitingGrant(name, _):
            tried.insert(name)
            return [.closeConnection] + tryNext()
        default:
            return []
        }
    }

    private mutating func grantReceived(_ grant: PairingGrant, at now: TimeInterval) -> [Effect] {
        guard case let .awaitingGrant(_, mac) = phase else { return [] }
        guard let mac else { return failCurrent() }
        let record = PairingRecord(
            peerID: mac.deviceID,
            peerName: mac.deviceName,
            pairingID: grant.pairingID,
            secret: grant.secret,
            pairedAt: now
        )
        code = nil
        phase = .paired(record)
        return [.save(record), .sendStored(grant.pairingID), .stopBrowsing]
    }
}

// Keyed by the peer's Keychain-held install id, not identifierForVendor (open question 10).
public struct PairingBook: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case loaded([PairingRecord])
        case paired(PairingRecord)
        case connected(peerID: UUID, at: TimeInterval)
        case forget(peerID: UUID)
    }

    public enum Effect: Equatable, Sendable {
        case save(PairingRecord)
        case delete(peerID: UUID)
        case dropConnections(peerID: UUID)
        case reloadCredentials
    }

    public private(set) var records: [PairingRecord]

    public init(_ records: [PairingRecord] = []) {
        self.records = records
    }

    public func record(pairingID: UUID) -> PairingRecord? {
        records.first { $0.pairingID == pairingID }
    }

    public func mostRecent(among peerIDs: [UUID]) -> PairingRecord? {
        records
            .filter { peerIDs.contains($0.peerID) }
            .max { ($0.lastConnectedAt ?? $0.pairedAt) < ($1.lastConnectedAt ?? $1.pairedAt) }
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .loaded(loaded):
            records = loaded
            return [.reloadCredentials]
        case let .paired(record):
            guard let index = records.firstIndex(where: { $0.peerID == record.peerID }) else {
                records.append(record)
                return [.save(record), .reloadCredentials]
            }
            records[index] = record
            return [.save(record), .dropConnections(peerID: record.peerID), .reloadCredentials]
        case let .connected(peerID, now):
            guard let index = records.firstIndex(where: { $0.peerID == peerID }) else { return [] }
            records[index].lastConnectedAt = now
            return [.save(records[index])]
        case let .forget(peerID):
            guard records.contains(where: { $0.peerID == peerID }) else { return [] }
            records.removeAll { $0.peerID == peerID }
            return [.delete(peerID: peerID), .dropConnections(peerID: peerID), .reloadCredentials]
        }
    }
}

public struct PairingHealth: Equatable, Sendable {
    public static let failuresBeforeBroken = 3

    public enum Event: Equatable, Sendable {
        case handshakeFailed(UUID)
        case handshakeSucceeded(UUID)
        case peerForgot(UUID)
    }

    public enum Effect: Equatable, Sendable {
        case markBroken(UUID)
        case markHealthy(UUID)
    }

    private var consecutiveFailures: [UUID: Int] = [:]

    public init() {}

    public func isBroken(_ deviceID: UUID) -> Bool {
        consecutiveFailures[deviceID, default: 0] >= Self.failuresBeforeBroken
    }

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .handshakeFailed(id):
            consecutiveFailures[id, default: 0] += 1
            return consecutiveFailures[id] == Self.failuresBeforeBroken ? [.markBroken(id)] : []
        case let .handshakeSucceeded(id):
            let wasBroken = isBroken(id)
            consecutiveFailures[id] = nil
            return wasBroken ? [.markHealthy(id)] : []
        case let .peerForgot(id):
            let wasBroken = isBroken(id)
            consecutiveFailures[id] = Self.failuresBeforeBroken
            return wasBroken ? [] : [.markBroken(id)]
        }
    }
}
