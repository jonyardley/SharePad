import AVFoundation

struct CaptureDevice: Equatable, Identifiable {
    let id: String
    let name: String
}

final class DeviceMonitor: NSObject {
    let devices: AsyncStream<[CaptureDevice]>
    private let continuation: AsyncStream<[CaptureDevice]>.Continuation
    private let discovery: AVCaptureDevice.DiscoverySession
    private var observation: NSKeyValueObservation?

    override init() {
        discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        (devices, continuation) = AsyncStream.makeStream(of: [CaptureDevice].self)
        super.init()
    }

    /// Devices appear asynchronously after the CMIO opt-in, so we KVO `devices`
    /// rather than reading it once. `.initial` also covers an already-connected
    /// iPad at launch. (DESIGN.md §6.3)
    func start() {
        observation = discovery.observe(\.devices, options: [
            .initial,
            .new,
        ]) { [continuation] session, _ in
            continuation.yield(session.devices.map { CaptureDevice(
                id: $0.uniqueID,
                name: $0.localizedName
            ) })
        }
    }

    func stop() {
        observation = nil
        continuation.finish()
    }
}
