import CoreMedia
import Foundation
import ReplayKit
import SpikeWire
import UIKit

/// ReplayKit in-app capture (`RPScreenRecorder.startCapture`) feeding the shared
/// encode/transport path. In-app capture only runs while this app is foregrounded,
/// which is why the drawing surface has to live in this app rather than being any
/// third-party whiteboard: that constraint is the architecture, not a shortcut.
@Observable
final class ScreenCaptureSender {
    var statusText = "idle"
    var isCapturing = false
    var framesPerSecond: Double = 0
    var kilobitsPerSecond: Double = 0
    var droppedFrames = 0
    var encodedFrames = 0
    var errorText: String?

    private let sender: SpikeStreamSender
    private let recorder = RPScreenRecorder.shared()

    init(bitrate: Int = 8_000_000, expectedFrameRate: Int = 15) {
        sender = SpikeStreamSender(bitrate: bitrate, expectedFrameRate: expectedFrameRate)
        sender.onState = { [weak self] state in
            self?.statusText = state.label
        }
        sender.onStats = { [weak self] stats in
            self?.framesPerSecond = stats.framesPerSecond
            self?.kilobitsPerSecond = stats.kilobitsPerSecond
            self?.droppedFrames = stats.droppedFrames
            self?.encodedFrames = stats.encodedFrames
        }
    }

    func start() {
        guard !isCapturing else { return }
        errorText = nil
        sender.connect()

        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        recorder.startCapture { [weak self] sampleBuffer, bufferType, _ in
            guard bufferType == .video,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            // Stamped here, before encode, so the receiver's figure includes
            // everything the wireless path adds.
            self?.sender.submit(
                pixelBuffer: pixelBuffer,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                captureWallClock: Date().timeIntervalSince1970
            )
        } completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.errorText = error.localizedDescription
                    self.statusText = "capture refused"
                    self.sender.stop()
                } else {
                    self.isCapturing = true
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        }
    }

    func stop() {
        guard isCapturing else {
            sender.stop()
            return
        }
        recorder.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCapturing = false
                UIApplication.shared.isIdleTimerDisabled = false
                if let error {
                    self.errorText = error.localizedDescription
                }
                self.sender.stop()
            }
        }
    }
}
