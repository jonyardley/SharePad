import Foundation

public enum SpikeWireError: Error {
    case truncated
    case unknownMessageType(UInt8)
}

public enum SpikeService {
    public static let type = "_sharepadspike._tcp"
    public static let headerLength = 5
}

public struct SpikeFrame {
    public let sequence: UInt32
    public let isKeyframe: Bool
    /// Sender wall clock (`timeIntervalSince1970`) sampled the instant ReplayKit
    /// handed the frame over, i.e. before encode. Compared against the receiver's
    /// clock via `ClockSync`, never directly.
    public let captureWallClock: Double
    public let avcc: Data

    public init(sequence: UInt32, isKeyframe: Bool, captureWallClock: Double, avcc: Data) {
        self.sequence = sequence
        self.isKeyframe = isKeyframe
        self.captureWallClock = captureWallClock
        self.avcc = avcc
    }
}

public enum SpikeMessage {
    case config(width: Int32, height: Int32, parameterSets: [Data])
    case frame(SpikeFrame)
    case ping(t1: Double)
    case pong(t1: Double, t2: Double)

    var typeCode: UInt8 {
        switch self {
        case .config: 1
        case .frame: 2
        case .ping: 3
        case .pong: 4
        }
    }

    public func encoded() -> Data {
        var body = ByteWriter()
        switch self {
        case let .config(width, height, parameterSets):
            body.u32(UInt32(bitPattern: width))
            body.u32(UInt32(bitPattern: height))
            body.u8(UInt8(min(parameterSets.count, 255)))
            for set in parameterSets.prefix(255) {
                body.u32(UInt32(set.count))
                body.bytes(set)
            }
        case let .frame(frame):
            body.u32(frame.sequence)
            body.u8(frame.isKeyframe ? 1 : 0)
            body.f64(frame.captureWallClock)
            body.bytes(frame.avcc)
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

    public static func decode(typeCode: UInt8, payload: Data) throws -> SpikeMessage {
        var reader = ByteReader(payload)
        switch typeCode {
        case 1:
            let width = try Int32(bitPattern: reader.u32())
            let height = try Int32(bitPattern: reader.u32())
            let count = try reader.u8()
            var sets: [Data] = []
            for _ in 0 ..< count {
                let length = try Int(reader.u32())
                try sets.append(reader.bytes(length))
            }
            return .config(width: width, height: height, parameterSets: sets)
        case 2:
            let sequence = try reader.u32()
            let isKeyframe = try reader.u8() == 1
            let captureWallClock = try reader.f64()
            return .frame(SpikeFrame(
                sequence: sequence,
                isKeyframe: isKeyframe,
                captureWallClock: captureWallClock,
                avcc: reader.rest()
            ))
        case 3:
            return try .ping(t1: reader.f64())
        case 4:
            return try .pong(t1: reader.f64(), t2: reader.f64())
        default:
            throw SpikeWireError.unknownMessageType(typeCode)
        }
    }
}

struct ByteWriter {
    var data = Data()

    mutating func u8(_ value: UInt8) {
        data.append(value)
    }

    mutating func u32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func u64(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func f64(_ value: Double) {
        u64(value.bitPattern)
    }

    mutating func bytes(_ value: Data) {
        data.append(value)
    }
}

struct ByteReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    private mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw SpikeWireError.truncated }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return data[start ..< end]
    }

    mutating func u8() throws -> UInt8 {
        guard let byte = try take(1).first else { throw SpikeWireError.truncated }
        return byte
    }

    mutating func u32() throws -> UInt32 {
        try take(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func u64() throws -> UInt64 {
        try take(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func f64() throws -> Double {
        try Double(bitPattern: u64())
    }

    mutating func bytes(_ count: Int) throws -> Data {
        try Data(take(count))
    }

    mutating func rest() -> Data {
        let start = data.index(data.startIndex, offsetBy: offset)
        offset = data.count
        return Data(data[start...])
    }
}
