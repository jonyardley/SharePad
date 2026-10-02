import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

// @unchecked: driven from the caller's queue; VideoToolbox's thread only reads
// the callbacks, which are set once before the first decode.
public final class H264Decoder: @unchecked Sendable {
    public struct DecodedFrame: @unchecked Sendable {
        public let pixelBuffer: CVPixelBuffer
        public let sequence: UInt32
        public let captureWallClock: Double?
        public let decodeSeconds: Double
    }

    public var onDecodedFrame: (@Sendable (DecodedFrame) -> Void)?
    public var onDecodeFailed: (@Sendable (OSStatus) -> Void)?

    private let log = Logger(subsystem: "co.sharepad.wire", category: "decoder")

    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var configuredSets: [Data] = []

    public init() {}

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    public var isConfigured: Bool {
        format != nil
    }

    // Config is resent with every keyframe that changes parameter sets, so an
    // identical one must not tear down a working session.
    public func configure(parameterSets: [Data]) {
        guard !parameterSets.isEmpty, parameterSets != configuredSets else { return }

        let buffers = parameterSets.map { set -> (UnsafeMutablePointer<UInt8>, Int) in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(set.count, 1))
            set.copyBytes(to: pointer, count: set.count)
            return (pointer, set.count)
        }
        defer { buffers.forEach { $0.0.deallocate() } }

        let pointers = buffers.map { UnsafePointer($0.0) }
        let sizes = buffers.map(\.1)

        var created: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer -> OSStatus in
                guard let pointerBase = pointerBuffer.baseAddress,
                      let sizeBase = sizeBuffer.baseAddress
                else { return -1 }
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointerBase,
                    parameterSetSizes: sizeBase,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &created
                )
            }
        }

        guard status == noErr, let created else {
            log.error("format description failed: \(status)")
            onDecodeFailed?(status)
            return
        }

        teardownSession()
        format = created
        configuredSets = parameterSets
        let dimensions = CMVideoFormatDescriptionGetDimensions(created)
        log.info("configured \(dimensions.width)x\(dimensions.height)")
    }

    public func decode(frame: EncodedVideoFrame) {
        guard let format, let session = prepareSession(format: format),
              let sampleBuffer = makeSampleBuffer(avcc: frame.avcc, format: format)
        else {
            onDecodeFailed?(kVTInvalidSessionErr)
            return
        }

        let start = CFAbsoluteTimeGetCurrent()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self else { return }
            guard status == noErr, let imageBuffer else {
                log.error("frame \(frame.sequence) failed: \(status)")
                onDecodeFailed?(status)
                return
            }
            onDecodedFrame?(DecodedFrame(
                pixelBuffer: imageBuffer,
                sequence: frame.sequence,
                captureWallClock: frame.captureWallClock,
                decodeSeconds: CFAbsoluteTimeGetCurrent() - start
            ))
        }

        if status != noErr {
            log.error("submit \(frame.sequence) failed: \(status)")
            teardownSession()
            onDecodeFailed?(status)
        }
    }

    private func prepareSession(format: CMVideoFormatDescription) -> VTDecompressionSession? {
        if let session { return session }

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var created: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &created
        )
        guard status == noErr, let created else {
            log.error("VTDecompressionSessionCreate failed: \(status)")
            return nil
        }
        VTSessionSetProperty(
            created,
            key: kVTDecompressionPropertyKey_RealTime,
            value: true as CFBoolean
        )
        session = created
        return created
    }

    private func teardownSession() {
        guard let session else { return }
        VTDecompressionSessionInvalidate(session)
        self.session = nil
    }

    private func makeSampleBuffer(avcc: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        let count = avcc.count
        guard count > 0, let block = malloc(count) else { return nil }
        avcc.copyBytes(to: block.assumingMemoryBound(to: UInt8.self), count: count)

        var blockBuffer: CMBlockBuffer?
        // kCFAllocatorMalloc hands ownership of `block` to the block buffer.
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: block,
            blockLength: count,
            blockAllocator: kCFAllocatorMalloc,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            free(block)
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        var sizes = [count]
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sizes,
            sampleBufferOut: &sampleBuffer
        )
        return status == noErr ? sampleBuffer : nil
    }
}
