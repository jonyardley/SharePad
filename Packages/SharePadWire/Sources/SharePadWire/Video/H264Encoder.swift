import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

// @unchecked: the session is touched only from the caller's queue; the in-flight
// count is the one value VideoToolbox's thread writes, and it sits behind a lock.
public final class H264Encoder: @unchecked Sendable {
    public struct EncodedFrame: @unchecked Sendable {
        public let avcc: Data
        public let isKeyframe: Bool
        public let parameterSets: [Data]
        public let width: Int32
        public let height: Int32
        public let presentationTime: CMTime
    }

    public var onEncodedFrame: (@Sendable (EncodedFrame) -> Void)?

    private let settings: EncoderSettings
    private let log = Logger(subsystem: "co.sharepad.wire", category: "encoder")
    private var expectedFrameRate: Double = 60
    private var session: VTCompressionSession?
    private var sessionWidth: Int32 = 0
    private var sessionHeight: Int32 = 0
    // Owned here rather than by the caller because only the encoder sees every
    // path a frame can die on; a count that leaks would stall the stream for good.
    private let pending = OSAllocatedUnfairLock(initialState: 0)

    public init(settings: EncoderSettings = EncoderSettings()) {
        self.settings = settings
    }

    deinit {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
    }

    public var pendingFrames: Int {
        pending.withLock { $0 }
    }

    public func updateExpectedFrameRate(_ rate: Double) {
        expectedFrameRate = rate
        if let session {
            set(session, kVTCompressionPropertyKey_ExpectedFrameRate, rate as CFNumber)
        }
    }

    public func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        forceKeyframe: Bool
    ) {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        // VideoToolbox sessions cannot be resized, and iPad rotation changes the
        // capture size mid-stream, so a new size rebuilds the session.
        guard let session = prepareSession(width: width, height: height) else { return }

        let properties: CFDictionary? = forceKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            : nil
        addPending(1)
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: properties,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            self?.addPending(-1)
            guard status == noErr, let sampleBuffer else { return }
            self?.handle(sampleBuffer, width: width, height: height)
        }
        if status != noErr {
            addPending(-1)
            log.error("submit failed: \(status)")
        }
    }

    public func invalidate() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        sessionWidth = 0
        sessionHeight = 0
        pending.withLock { $0 = 0 }
    }

    private func addPending(_ delta: Int) {
        pending.withLock { $0 = max(0, $0 + delta) }
    }

    private func prepareSession(width: Int32, height: Int32) -> VTCompressionSession? {
        if let session, width == sessionWidth, height == sessionHeight {
            return session
        }
        invalidate()

        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &created
        )
        guard status == noErr, let created else {
            log.error("VTCompressionSessionCreate failed: \(status)")
            return nil
        }

        // Frame reordering would add at least one frame of structural delay.
        // Keyframes come on demand; the duration cap is only a safety net, and
        // there is deliberately no frame-count cap (specs/wireless-product.md §8).
        set(created, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(created, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(created, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(created, kVTCompressionPropertyKey_AverageBitRate, settings.averageBitRate as CFNumber)
        // kVTCompressionPropertyKey_DataRateLimits takes flattened [bytes, seconds, ...] pairs.
        set(
            created,
            kVTCompressionPropertyKey_DataRateLimits,
            settings.dataRateLimits
                .flatMap { [$0.bytes as NSNumber, $0.seconds as NSNumber] } as CFArray
        )
        set(created, kVTCompressionPropertyKey_ExpectedFrameRate, expectedFrameRate as CFNumber)
        set(
            created,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            settings.keyframeIntervalSeconds as CFNumber
        )
        VTCompressionSessionPrepareToEncodeFrames(created)

        session = created
        sessionWidth = width
        sessionHeight = height
        let rate = expectedFrameRate
        log.info("session \(width)x\(height) at \(rate) fps")
        return created
    }

    private func set(_ session: VTCompressionSession, _ key: CFString, _ value: CFTypeRef) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            log.error("property \(key as String) rejected: \(status)")
        }
    }

    private func handle(_ sampleBuffer: CMSampleBuffer, width: Int32, height: Int32) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let avcc = Self.data(from: blockBuffer)
        else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[String: Any]]
        let notSync = attachments?
            .first?[kCMSampleAttachmentKey_NotSync as String] as? Bool ?? false
        let isKeyframe = !notSync

        var parameterSets: [Data] = []
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSets = Self.parameterSets(from: format)
        }

        onEncodedFrame?(EncodedFrame(
            avcc: avcc,
            isKeyframe: isKeyframe,
            parameterSets: parameterSets,
            width: width,
            height: height,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        ))
    }

    static func data(from blockBuffer: CMBlockBuffer) -> Data? {
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: base
            )
        }
        return status == kCMBlockBufferNoErr ? data : nil
    }

    static func parameterSets(from format: CMFormatDescription) -> [Data] {
        var count = 0
        let probe = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil
        )
        guard probe == noErr else { return [] }

        var sets: [Data] = []
        for index in 0 ..< count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            if status == noErr, let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        return sets
    }
}
