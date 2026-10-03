import CoreMedia
import ImageIO
import os
import ReplayKit

struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let orientation: CGImagePropertyOrientation
    var isCanvasOnly = false
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
        recorder.startCapture(
            handler: Self.frameHandler(onFrame),
            completionHandler: Self.completion(log: log, completion)
        )
    }

    @MainActor
    func stop(completion: @escaping @MainActor @Sendable () -> Void) {
        recorder.stopCapture(handler: Self.completion(log: log) { _ in completion() })
    }

    // These handlers are built outside any actor: ReplayKit calls them on its own
    // queue, and a closure formed in a @MainActor method would trap there under Swift 6.
    private nonisolated static func completion(
        log: Logger,
        _ onMain: @escaping @MainActor @Sendable (_ succeeded: Bool) -> Void
    ) -> @Sendable (Error?) -> Void {
        { error in
            if let error {
                log.info("capture call ended with: \(error.localizedDescription)")
            }
            let succeeded = error == nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onMain(succeeded) }
            }
        }
    }

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
