import Foundation
import Network

// The Mac's install id rides in its Bonjour TXT record so an iPad can match a
// service to a pairing without a handshake per guess (specs/wireless-pairing-ui.md).
public extension WireService {
    static let deviceIDKey = "id"

    static func txtRecord(deviceID: UUID) -> NWTXTRecord {
        NWTXTRecord([deviceIDKey: deviceID.uuidString])
    }

    static func deviceID(in record: NWTXTRecord) -> UUID? {
        record[deviceIDKey].flatMap(UUID.init(uuidString:))
    }
}

public struct AdvertisedService: Equatable, Sendable {
    public let name: String
    public let deviceID: UUID?

    public init(name: String, deviceID: UUID?) {
        self.name = name
        self.deviceID = deviceID
    }
}

public struct PairedService: Equatable, Sendable {
    public let name: String
    public let record: PairingRecord
}

public enum PairedServices {
    public static func rank(
        _ services: [AdvertisedService],
        pairings: [PairingRecord]
    ) -> [PairedService] {
        services
            .compactMap { service -> PairedService? in
                guard let id = service.deviceID,
                      let record = pairings.first(where: { $0.peerID == id }) else { return nil }
                return PairedService(name: service.name, record: record)
            }
            .sorted { lastUsed($0.record) > lastUsed($1.record) }
    }

    private static func lastUsed(_ record: PairingRecord) -> TimeInterval {
        record.lastConnectedAt ?? record.pairedAt
    }
}
