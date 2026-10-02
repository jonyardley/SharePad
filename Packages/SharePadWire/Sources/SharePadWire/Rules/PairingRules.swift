import Foundation

public struct PairingOffer: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    public let pairingID: UUID
    public let issuedAt: TimeInterval

    public init(pairingID: UUID, issuedAt: TimeInterval) {
        self.pairingID = pairingID
        self.issuedAt = issuedAt
    }

    public func isExpired(at now: TimeInterval) -> Bool {
        now - issuedAt >= Self.lifetime
    }
}

public struct PairedDevice: Equatable, Sendable {
    public let deviceID: UUID
    public let name: String
    public let pairedAt: TimeInterval

    public init(deviceID: UUID, name: String, pairedAt: TimeInterval) {
        self.deviceID = deviceID
        self.name = name
        self.pairedAt = pairedAt
    }
}

public struct PairingWindow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        case offering(PairingOffer)
        case paired(PairedDevice)
        case expired
    }

    public enum RejectReason: Equatable, Sendable {
        case unknownCode
        case expired
        case alreadyUsed
    }

    public enum Event: Equatable, Sendable {
        case open(PairingOffer)
        case handshakeSucceeded(pairingID: UUID, peer: Hello, at: TimeInterval)
        case tick(at: TimeInterval)
        case close
    }

    public enum Effect: Equatable, Sendable {
        case startAdvertising
        case stopAdvertising
        case store(PairedDevice)
        case reject(RejectReason)
    }

    public private(set) var phase: Phase = .closed

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .open(offer):
            phase = .offering(offer)
            return [.startAdvertising]
        case let .handshakeSucceeded(pairingID, peer, now):
            return redeem(pairingID: pairingID, peer: peer, at: now)
        case let .tick(now):
            guard case let .offering(offer) = phase, offer.isExpired(at: now) else { return [] }
            phase = .expired
            return [.stopAdvertising]
        case .close:
            let wasOffering = if case .offering = phase {
                true
            } else {
                false
            }
            phase = .closed
            return wasOffering ? [.stopAdvertising] : []
        }
    }

    private mutating func redeem(pairingID: UUID, peer: Hello, at now: TimeInterval) -> [Effect] {
        switch phase {
        case let .offering(offer) where offer.pairingID == pairingID:
            guard !offer.isExpired(at: now) else {
                phase = .expired
                return [.reject(.expired), .stopAdvertising]
            }
            let device = PairedDevice(deviceID: peer.deviceID, name: peer.deviceName, pairedAt: now)
            phase = .paired(device)
            return [.store(device), .stopAdvertising]
        case let .paired(device) where device.deviceID != peer.deviceID:
            return [.reject(.alreadyUsed)]
        case .paired:
            return []
        default:
            return [.reject(.unknownCode)]
        }
    }
}

public struct PairedDevices: Equatable, Sendable {
    public private(set) var devices: [PairedDevice]

    public init(_ devices: [PairedDevice] = []) {
        self.devices = devices
    }

    public mutating func store(_ device: PairedDevice) {
        if let index = devices.firstIndex(where: { $0.deviceID == device.deviceID }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    public mutating func forget(_ deviceID: UUID) {
        devices.removeAll { $0.deviceID == deviceID }
    }
}

public struct PairingHealth: Equatable, Sendable {
    public static let failuresBeforeBroken = 3

    public enum Event: Equatable, Sendable {
        case handshakeFailed(UUID)
        case handshakeSucceeded(UUID)
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
        }
    }
}
