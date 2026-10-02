import CoreMedia
import ImageIO
import os
import ReplayKit

struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let orientation: CGImagePropertyOrientation
}

protocol ScreenRecording: AnyObject {
    @MainActor
    func start(
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    )
    @MainActor
    func stop(completion: @escaping @MainActor @Sendable () -> Void)
}

final class ScreenRecorder: ScreenRecording {
    private let recorder = RPScreenRecorder.shared()
    private let log = Logger(subsystem: "co.sharepad.ipad", category: "capture")

    @MainActor
    func start(
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        let log = log
        recorder.startCapture(
            handler: Self.frameHandler(onFrame),
            completionHandler: { error in
                if let error {
                    log.error("capture refused: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { completion(error == nil) }
                }
            }
        )
    }

    @MainActor
    func stop(completion: @escaping @MainActor @Sendable () -> Void) {
        let log = log
        recorder.stopCapture { error in
            if let error {
                log.info("stop capture: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion() }
            }
        }
    }

    // Built outside any actor: ReplayKit calls it on its own queue, and a closure
    // formed in a @MainActor method would trap on that queue under Swift 6.
    private nonisolated static func frameHandler(
        _ onFrame: @escaping @Sendable (CapturedFrame) -> Void
    ) -> @Sendable (CMSampleBuffer, RPSampleBufferType, Error?) -> Void {
        { sampleBuffer, type, _ in
            guard type == .video,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            onFrame(CapturedFrame(
                pixelBuffer: pixelBuffer,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                orientation: orientation(of: sampleBuffer)
            ))
        }
    }

    private nonisolated static func orientation(of sampleBuffer: CMSampleBuffer)
        -> CGImagePropertyOrientation {
        let value = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber
        return value.flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
    }
}
