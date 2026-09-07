import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public final class H264Encoder {
    public struct EncodedFrame {
        public let avcc: Data
        public let isKeyframe: Bool
        public let parameterSets: [Data]
        public let width: Int32
        public let height: Int32
        public let presentationTime: CMTime
    }

    public var onEncodedFrame: ((EncodedFrame) -> Void)?

    private let bitrate: Int
    private let expectedFrameRate: Int
    private var session: VTCompressionSession?
    private var sessionWidth: Int32 = 0
    private var sessionHeight: Int32 = 0

    public init(bitrate: Int = 8_000_000, expectedFrameRate: Int = 15) {
        self.bitrate = bitrate
        self.expectedFrameRate = expectedFrameRate
    }

    deinit {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
    }

    public func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        // iPad rotation changes the capture dimensions mid-stream; VideoToolbox
        // cannot be resized, so the session is rebuilt and the next frame carries
        // fresh parameter sets.
        guard let session = prepareSession(width: width, height: height) else { return }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer else { return }
            self?.handle(sampleBuffer, width: width, height: height)
        }
    }

    public func invalidate() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        sessionWidth = 0
        sessionHeight = 0
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
            print("[encoder] VTCompressionSessionCreate failed: \(status)")
            return nil
        }

        // Latency-first configuration: real-time mode, no B-frames (frame
        // reordering would add at least one frame of structural delay), and a
        // 2 s keyframe interval so a mid-stream receiver recovers quickly.
        set(created, kVTCompressionPropertyKey_RealTime, true as CFBoolean)
        set(created, kVTCompressionPropertyKey_AllowFrameReordering, false as CFBoolean)
        set(created, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(created, kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(created, kVTCompressionPropertyKey_ExpectedFrameRate, expectedFrameRate as CFNumber)
        set(
            created,
            kVTCompressionPropertyKey_MaxKeyFrameInterval,
            (expectedFrameRate * 2) as CFNumber
        )
        set(created, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 2 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(created)

        session = created
        sessionWidth = width
        sessionHeight = height
        print(
            "[encoder] session \(width)x\(height) @ \(expectedFrameRate) fps, \(bitrate / 1000) kbps"
        )
        return created
    }

    private func set(_ session: VTCompressionSession, _ key: CFString, _ value: CFTypeRef) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            print("[encoder] property \(key) rejected: \(status)")
        }
    }

    private func handle(_ sampleBuffer: CMSampleBuffer, width: Int32, height: Int32) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let avcc = Self.data(from: blockBuffer)
        else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        )
            as? [[String: Any]]
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
