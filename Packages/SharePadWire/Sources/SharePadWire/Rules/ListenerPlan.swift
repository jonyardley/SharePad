import Foundation

public struct ListenerPlan: Equatable, Sendable {
    public let pairingCode: PairingCode?
    public let paired: [PairingRecord]

    public static func make(
        offering code: PairingCode?,
        paired: [PairingRecord],
        allowWireless: Bool
    ) -> ListenerPlan? {
        let admitted = allowWireless ? paired : []
        guard code != nil || !admitted.isEmpty else { return nil }
        return ListenerPlan(pairingCode: code, paired: admitted)
    }

    // Recording a connection time must not replace the listener; only keys count.
    public static func == (lhs: ListenerPlan, rhs: ListenerPlan) -> Bool {
        lhs.pairingCode == rhs.pairingCode && lhs.keys == rhs.keys
    }

    private var keys: [UUID: LinkSecret] {
        Dictionary(
            paired.map { ($0.pairingID, $0.secret) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public var security: LinkSecurity {
        .server(pairingCode: pairingCode, paired: paired)
    }
}
