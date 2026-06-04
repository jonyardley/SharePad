@testable import SharePad
import XCTest

final class DeviceSelectionTests: XCTestCase {
    private func device(_ id: String) -> CaptureDevice {
        CaptureDevice(id: id, name: "Device \(id)")
    }

    func testKeepsCurrentWhenPresent() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(pickDevice(from: devices, current: "b", lastUsed: "a")?.id, "b")
    }

    func testCurrentTakesPrecedenceOverLastUsed() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(pickDevice(from: devices, current: "a", lastUsed: "b")?.id, "a")
    }

    func testFallsBackToLastUsedWhenCurrentAbsent() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(pickDevice(from: devices, current: "gone", lastUsed: "b")?.id, "b")
    }

    func testFallsBackToFirstWhenNeitherPresent() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(pickDevice(from: devices, current: "gone", lastUsed: "also-gone")?.id, "a")
    }

    func testFallsBackToFirstWhenBothNil() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(pickDevice(from: devices, current: nil, lastUsed: nil)?.id, "a")
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(pickDevice(from: [], current: "a", lastUsed: "b"))
    }

    func testResolveTeardownWhenEmpty() {
        XCTAssertEqual(resolveDevice(devices: [], current: "a", lastUsed: "b"), .teardown)
    }

    func testResolveKeepsCurrentWhenPresent() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(
            resolveDevice(devices: devices, current: "a", lastUsed: nil),
            .keep(device("a"))
        )
    }

    func testResolveKeepsCurrentWhenSecondDeviceAppears() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(
            resolveDevice(devices: devices, current: "a", lastUsed: nil),
            .keep(device("a"))
        )
    }

    func testResolveSwitchesWhenCurrentVanishesWithOtherPresent() {
        let devices = [device("b"), device("c")]
        XCTAssertEqual(
            resolveDevice(devices: devices, current: "a", lastUsed: nil),
            .switchTo(device("b"))
        )
    }

    func testResolveSwitchesToLastUsedWhenCurrentNil() {
        let devices = [device("a"), device("b")]
        XCTAssertEqual(
            resolveDevice(devices: devices, current: nil, lastUsed: "b"),
            .switchTo(device("b"))
        )
    }
}
