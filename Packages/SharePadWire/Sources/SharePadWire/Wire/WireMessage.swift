import Foundation

public enum WireService {
    public static let type = "_sharepad._tcp"
    public static let headerLength = 5
    public static let maximumPayloadLength = 16 * 1024 * 1024
}

public enum WireProtocol {
    public static let version: UInt16 = 1
    public static let supportedVersions: ClosedRange<UInt16> = 1 ... 1
}

public enum WireError: Error, Equatable {
    case truncated
    case unknownMessageType(UInt8)
    case payloadTooLarge(Int)
    case invalidText
}

public struct Hello: Equatable, Sendable {
    public let protocolVersion: UInt16
    public let deviceID: UUID
    public let deviceName: String

    public init(
        protocolVersion: UInt16 = WireProtocol.version,
        deviceID: UUID,
        deviceName: String
    ) {
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

public struct CanvasRect: Equatable, Sendable {
    public let x: UInt32
    public let y: UInt32
    public let width: UInt32
    public let height: UInt32

    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func whole(width: Int32, height: Int32) -> CanvasRect {
        CanvasRect(x: 0, y: 0, width: UInt32(max(width, 0)), height: UInt32(max(height, 0)))
    }
}

public struct StreamConfig: Equatable, Sendable {
    public let width: Int32
    public let height: Int32
    public let canvas: CanvasRect
    public let parameterSets: [Data]

    public init(width: Int32, height: Int32, canvas: CanvasRect, parameterSets: [Data]) {
        self.width = width
        self.height = height
        self.canvas = canvas
        self.parameterSets = parameterSets
    }
}

public struct EncodedVideoFrame: Equatable, Sendable {
    public let sequence: UInt32
    public let isKeyframe: Bool
    // Sender wall clock at capture, before encode; only comparable to the receiver's
    // clock through ClockSync.
    public let captureWallClock: Double?
    public let avcc: Data

    public init(sequence: UInt32, isKeyframe: Bool, captureWallClock: Double?, avcc: Data) {
        self.sequence = sequence
        self.isKeyframe = isKeyframe
        self.captureWallClock = captureWallClock
        self.avcc = avcc
    }
}

// The reason rides as an optional trailing byte on `pause`, not a protocol bump:
// version 1 peers ignore the byte, and a missing or unknown one reads as
// `unspecified` (specs/wireless-product.md §10, W4b decision 5).
public enum PauseReason: UInt8, Equatable, Sendable {
    case unspecified = 0
    case cable = 1
    case trial = 2
}

public enum WireMessage: Equatable, Sendable {
    case hello(Hello)
    case config(StreamConfig)
    case frame(EncodedVideoFrame)
    case requestKeyframe
    case pause(PauseReason)
    case resume
    case ping(t1: Double)
    case pong(t1: Double, t2: Double)

    // Type codes are permanent: a peer on another protocol version still has to
    // read `hello` to learn that the versions differ.
    var typeCode: UInt8 {
        switch self {
        case .hello: 1
        case .config: 2
        case .frame: 3
        case .requestKeyframe: 4
        case .pause: 5
        case .resume: 6
        case .ping: 7
        case .pong: 8
        }
    }

    public func encoded() -> Data {
        var body = ByteWriter()
        switch self {
        case let .hello(hello):
            body.u16(hello.protocolVersion)
            body.uuid(hello.deviceID)
            body.text(hello.deviceName)
        case let .config(config):
            body.u32(UInt32(bitPattern: config.width))
            body.u32(UInt32(bitPattern: config.height))
            body.u32(config.canvas.x)
            body.u32(config.canvas.y)
            body.u32(config.canvas.width)
            body.u32(config.canvas.height)
            body.u8(UInt8(min(config.parameterSets.count, 255)))
            for set in config.parameterSets.prefix(255) {
                body.u32(UInt32(set.count))
                body.bytes(set)
            }
        case let .frame(frame):
            body.u32(frame.sequence)
            body.u8(frame.isKeyframe ? 1 : 0)
            body.f64(frame.captureWallClock ?? 0)
            body.bytes(frame.avcc)
        case let .pause(reason):
            body.u8(reason.rawValue)
        case .requestKeyframe, .resume:
            break
        case let .ping(t1):
            body.f64(t1)
        case let .pong(t1, t2):
            body.f64(t1)
            body.f64(t2)
        }

        var out = ByteWriter()
        out.u8(typeCode)
        out.u32(UInt32(body.data.count))
        out.bytes(body.data)
        return out.data
    }

    public static func header(_ header: Data) throws -> (typeCode: UInt8, length: Int) {
        var reader = ByteReader(header)
        let typeCode = try reader.u8()
        let length = try Int(reader.u32())
        guard length <= WireService.maximumPayloadLength else {
            throw WireError.payloadTooLarge(length)
        }
        return (typeCode, length)
    }

    public static func decode(typeCode: UInt8, payload: Data) throws -> WireMessage {
        var reader = ByteReader(payload)
        switch typeCode {
        case 1:
            return try .hello(Hello(
                protocolVersion: reader.u16(),
                deviceID: reader.uuid(),
                deviceName: reader.text()
            ))
        case 2:
            return try .config(decodeConfig(&reader))
        case 3:
            let sequence = try reader.u32()
            let isKeyframe = try reader.u8() == 1
            let captureWallClock = try reader.f64()
            return .frame(EncodedVideoFrame(
                sequence: sequence,
                isKeyframe: isKeyframe,
                captureWallClock: captureWallClock == 0 ? nil : captureWallClock,
                avcc: reader.rest()
            ))
        case 4:
            return .requestKeyframe
        case 5:
            return .pause(PauseReason(rawValue: payload.first ?? 0) ?? .unspecified)
        case 6:
            return .resume
        case 7:
            return try .ping(t1: reader.f64())
        case 8:
            return try .pong(t1: reader.f64(), t2: reader.f64())
        default:
            throw WireError.unknownMessageType(typeCode)
        }
    }

    private static func decodeConfig(_ reader: inout ByteReader) throws -> StreamConfig {
        let width = try Int32(bitPattern: reader.u32())
        let height = try Int32(bitPattern: reader.u32())
        let canvas = try CanvasRect(
            x: reader.u32(),
            y: reader.u32(),
            width: reader.u32(),
            height: reader.u32()
        )
        let count = try reader.u8()
        var sets: [Data] = []
        for _ in 0 ..< count {
            let length = try Int(reader.u32())
            try sets.append(reader.bytes(length))
        }
        return StreamConfig(width: width, height: height, canvas: canvas, parameterSets: sets)
    }
}
