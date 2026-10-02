import CoreMedia
import CoreVideo
import SharePadWire
import UIKit

struct LinkCallbacks: Sendable {
    var onStatus: @MainActor @Sendable (LinkStatus) -> Void
    var onLocalNetworkDenied: @MainActor @Sendable (Bool) -> Void
    var onPairedEvent: @MainActor @Sendable (StreamSender.PairedEvent) -> Void
}

protocol StreamLink: AnyObject, Sendable {
    func start()
    func stop()
    func setPairings(_ records: [PairingRecord])
    func setCanvas(_ rect: CanvasRect?)
    func submit(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, captureWallClock: Double)
}

final class PairedLink: StreamLink {
    private let sender: StreamSender

    @MainActor
    init(identity: Hello, lastMac: String?, pairings: [PairingRecord], callbacks: LinkCallbacks) {
        let lastSeen = LastSeenMac(lastMac)
        sender = StreamSender(
            deviceID: identity.deviceID,
            deviceName: identity.deviceName,
            lastPeer: lastMac,
            security: .paired(pairings),
            onPhase: { phase in
                MainActor.assumeIsolated {
                    callbacks.onStatus(lastSeen.status(for: phase))
                }
            },
            onLocalNetworkDenied: { denied in
                MainActor.assumeIsolated { callbacks.onLocalNetworkDenied(denied) }
            },
            onPairedEvent: { event in
                MainActor.assumeIsolated { callbacks.onPairedEvent(event) }
            }
        )
    }

    func start() {
        sender.start()
    }

    func stop() {
        sender.stop()
    }

    func setPairings(_ records: [PairingRecord]) {
        sender.setPairings(records)
    }

    func setCanvas(_ rect: CanvasRect?) {
        sender.setCanvas(rect)
    }

    func submit(pixelBuffer: CVPixelBuffer, presentationTime: CMTime,
                captureWallClock: Double) {
        sender.submit(
            pixelBuffer: pixelBuffer,
            presentationTime: presentationTime,
            captureWallClock: captureWallClock
        )
    }
}

@MainActor
private final class LastSeenMac {
    private var name: String?

    init(_ name: String?) {
        self.name = name
    }

    func status(for phase: SenderLink.Phase) -> LinkStatus {
        let status = LinkStatus(phase, lastMac: name)
        if let live = status.liveMac { name = live }
        return status
    }
}
