import Foundation

struct ByteWriter {
    static let maximumTextLength = 1024

    var data = Data()

    mutating func u8(_ value: UInt8) {
        data.append(value)
    }

    mutating func u16(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
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

    mutating func uuid(_ value: UUID) {
        withUnsafeBytes(of: value.uuid) { data.append(contentsOf: $0) }
    }

    mutating func text(_ value: String) {
        var trimmed = value
        while trimmed.utf8.count > ByteWriter.maximumTextLength {
            trimmed.removeLast()
        }
        u16(UInt16(trimmed.utf8.count))
        data.append(contentsOf: trimmed.utf8)
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
        guard count >= 0, offset + count <= data.count else { throw WireError.truncated }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return data[start ..< end]
    }

    mutating func u8() throws -> UInt8 {
        guard let byte = try take(1).first else { throw WireError.truncated }
        return byte
    }

    mutating func u16() throws -> UInt16 {
        try take(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
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

    mutating func uuid() throws -> UUID {
        let raw = try [UInt8](take(16))
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    mutating func text() throws -> String {
        let length = try Int(u16())
        guard let value = try String(data: take(length), encoding: .utf8) else {
            throw WireError.invalidText
        }
        return value
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
