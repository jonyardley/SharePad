import Foundation
@testable import SharePadWire
import XCTest

final class WireMessageTests: XCTestCase {
    private func roundTrip(_ message: WireMessage) throws -> WireMessage {
        let data = message.encoded()
        let (typeCode, length) = try WireMessage.header(data.prefix(WireService.headerLength))
        XCTAssertEqual(length, data.count - WireService.headerLength)
        return try WireMessage.decode(
            typeCode: typeCode,
            payload: data.dropFirst(WireService.headerLength)
        )
    }

    func testEveryMessageRoundTrips() throws {
        let messages: [WireMessage] = [
            .hello(Hello(deviceID: UUID(), deviceName: "Jon’s iPad ✏️")),
            .config(StreamConfig(
                width: 2388,
                height: 1668,
                canvas: CanvasRect(x: 0, y: 120, width: 2388, height: 1400),
                parameterSets: [Data([0x67, 0x64]), Data([0x68, 0xEE])]
            )),
            .frame(EncodedVideoFrame(
                sequence: 42,
                isKeyframe: true,
                captureWallClock: 1_790_000_000.125,
                avcc: Data(repeating: 7, count: 300)
            )),
            .requestKeyframe,
            .pause,
            .resume,
            .ping(t1: 12.5),
            .pong(t1: 12.5, t2: 13.25),
        ]
        for message in messages {
            XCTAssertEqual(try roundTrip(message), message)
        }
    }

    func testHelloCarriesTheProtocolVersion() throws {
        let hello = Hello(protocolVersion: 9, deviceID: UUID(), deviceName: "Future")
        XCTAssertEqual(try roundTrip(.hello(hello)), .hello(hello))
    }

    func testLongNamesAreTrimmedOnACharacterBoundary() throws {
        let name = String(repeating: "é", count: 2000)
        guard case let .hello(decoded) = try roundTrip(.hello(Hello(
            deviceID: UUID(),
            deviceName: name
        )))
        else { return XCTFail("not a hello") }
        XCTAssertLessThanOrEqual(decoded.deviceName.utf8.count, 1024)
        XCTAssertTrue(name.hasPrefix(decoded.deviceName))
    }

    func testOversizedPayloadIsRejected() {
        var header = Data([3])
        header.append(contentsOf: [0x7F, 0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try WireMessage.header(header)) { error in
            XCTAssertEqual(error as? WireError, .payloadTooLarge(0x7FFF_FFFF))
        }
    }

    func testUnknownTypeAndTruncationAreErrors() {
        XCTAssertThrowsError(try WireMessage.decode(typeCode: 200, payload: Data()))
        XCTAssertThrowsError(try WireMessage.decode(typeCode: 7, payload: Data([1, 2])))
    }

    func testUnknownCaptureTimeRoundTripsAsNil() throws {
        let frame = EncodedVideoFrame(
            sequence: 7,
            isKeyframe: false,
            captureWallClock: nil,
            avcc: Data([1, 2, 3])
        )
        XCTAssertEqual(try roundTrip(.frame(frame)), .frame(frame))
    }

    func testConfigDeclaringMoreSetsThanItCarriesIsTruncated() {
        var body = ByteWriter()
        for _ in 0 ..< 6 {
            body.u32(0)
        }
        body.u8(3)
        body.u32(2)
        body.bytes(Data([0x67, 0x64]))
        XCTAssertThrowsError(try WireMessage.decode(typeCode: 2, payload: body.data)) { error in
            XCTAssertEqual(error as? WireError, .truncated)
        }
    }

    func testHelloWithTrailingBytesStillDecodes() throws {
        let hello = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
        var data = WireMessage.hello(hello).encoded().dropFirst(WireService.headerLength)
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(try WireMessage.decode(typeCode: 1, payload: Data(data)), .hello(hello))
    }
}
