import CoreMedia
import CoreVideo
import SharePadWire
import UIKit

struct LinkCallbacks: Sendable {
    var onStatus: @MainActor @Sendable (LinkStatus) -> Void
    var onLocalNetworkDenied: @MainActor @Sendable (Bool) -> Void
}

// The seam W2b fills: a paired, TLS-PSK link conforms here and replaces
// `DevelopmentLink` without the model changing.
protocol StreamLink: AnyObject, Sendable {
    func start()
    func stop()
    func setCanvas(_ rect: CanvasRect?)
    func submit(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, captureWallClock: Double)
}

enum StreamLinks {
    @MainActor
    static func make(lastMac: String?, callbacks: LinkCallbacks) -> StreamLink {
        #if DEBUG
            DevelopmentLink(lastMac: lastMac, callbacks: callbacks)
        #else
            UnpairedLink(callbacks: callbacks)
        #endif
    }
}

#if DEBUG
    // Unauthenticated SharePadWire link: streams to any SharePad Mac on the Wi-Fi.
    // Debug builds only, until pairing and TLS land (specs/wireless-product.md §6).
    final class DevelopmentLink: StreamLink {
        private let sender: StreamSender

        @MainActor
        init(lastMac: String?, callbacks: LinkCallbacks) {
            let lastSeen = LastSeenMac(lastMac)
            sender = StreamSender(
                deviceID: UIDevice.current.identifierForVendor ?? UUID(),
                deviceName: UIDevice.current.name,
                lastPeer: lastMac,
                onPhase: { phase in
                    MainActor.assumeIsolated {
                        callbacks.onStatus(lastSeen.status(for: phase))
                    }
                },
                onLocalNetworkDenied: { denied in
                    MainActor.assumeIsolated { callbacks.onLocalNetworkDenied(denied) }
                }
            )
        }

        func start() {
            sender.start()
        }

        func stop() {
            sender.stop()
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
#endif

final class UnpairedLink: StreamLink {
    private let callbacks: LinkCallbacks

    init(callbacks: LinkCallbacks) {
        self.callbacks = callbacks
    }

    func start() {
        let callbacks = callbacks
        Task { @MainActor in callbacks.onStatus(.notPaired) }
    }

    func stop() {}

    func setCanvas(_: CanvasRect?) {}

    func submit(
        pixelBuffer _: CVPixelBuffer,
        presentationTime _: CMTime,
        captureWallClock _: Double
    ) {}
}
