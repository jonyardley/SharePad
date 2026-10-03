import Foundation
import SharePadWire

enum PairingState: Equatable {
    case unpaired
    case broken(String)
    case paired

    init(records: [PairingRecord], broken: Set<UUID>) {
        guard !records.isEmpty else {
            self = .unpaired
            return
        }
        let newestBroken = records
            .filter { broken.contains($0.peerID) }
            .max { ($0.lastConnectedAt ?? $0.pairedAt) < ($1.lastConnectedAt ?? $1.pairedAt) }
        self = newestBroken.map { .broken($0.peerName) } ?? .paired
    }
}

enum TypedCode {
    static let length = 24
    static let groupLength = 4

    // Crockford's lookalikes O, I and L stay as typed; PairingCode reads them as 0 and 1.
    private static let accepted = Set("0123456789ABCDEFGHIJKLMNOPQRSTVWXYZ")

    static func format(_ text: String) -> String {
        let characters = text.uppercased().filter(accepted.contains).prefix(length)
        return stride(from: 0, to: characters.count, by: groupLength).map { start in
            let begin = characters.index(characters.startIndex, offsetBy: start)
            let end = characters.index(begin, offsetBy: min(groupLength, characters.count - start))
            return String(characters[begin ..< end])
        }.joined(separator: "-")
    }

    static func code(from text: String) -> PairingCode? {
        PairingCode(typed: text)
    }

    static func code(scanned text: String) -> PairingCode? {
        if let url = URL(string: text), let code = PairingCode(invitation: url) { return code }
        return PairingCode(typed: text)
    }
}

struct PairingScreenContent: Equatable {
    static let macAppNote = "You also need SharePad on your Mac: sharepad.co"
    static let steps = [
        "On your Mac, click the SharePad icon in the menu bar, then Pair an iPad…",
        "Scan the code it shows.",
    ]
    static let recordPromptNote =
        "Each time you open SharePad, your iPad asks to record the screen. Tap Allow."

    let status: String?
    let isWorking: Bool
    let isPaired: Bool
    let showsMacAppNote: Bool

    init(phase: PadPairing.Phase, saveFailed: Bool, hasPairings: Bool) {
        showsMacAppNote = !hasPairings
        isPaired = if case .paired = phase {
            true
        } else {
            false
        }
        switch phase {
        case .searching, .trying, .awaitingGrant:
            isWorking = true
        case .idle, .paired, .failed:
            isWorking = false
        }
        status = Self.status(phase, saveFailed: saveFailed)
    }

    private static func status(_ phase: PadPairing.Phase, saveFailed: Bool) -> String? {
        if saveFailed { return "This iPad couldn’t save the pairing. Try again." }
        switch phase {
        case .idle:
            return nil
        case .searching:
            return "Looking for your Mac…"
        case let .trying(name), let .awaitingGrant(name, nil):
            return "Trying \(name)…"
        case let .awaitingGrant(_, mac?):
            return "Pairing with \(mac.deviceName)…"
        case let .paired(record):
            return "Paired with \(record.peerName)"
        case .failed(.noMacAccepted):
            return "No Mac accepted that code. Check it matches the one on your Mac, "
                + "and that both are on the same Wi-Fi."
        }
    }
}
