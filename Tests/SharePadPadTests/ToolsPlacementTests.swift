import CoreGraphics
@testable import SharePadPad
import XCTest

final class ToolsPlacementTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 744, height: 1133)
    private let palette = CGRect(x: 40, y: 1004.5, width: 664, height: 108.5)

    func testDockedPickerUsesTheReportedFrame() {
        let docked = CGRect(x: 0, y: 1033, width: 744, height: 100)
        let placement = ToolsPlacement.resolve(
            pickerVisible: true, reported: docked, measured: [palette], window: window
        )
        XCTAssertEqual(placement, ToolsPlacement(obstructions: [docked], isUnknown: false))
    }

    func testMovablePaletteUsesTheMeasuredFrame() {
        let placement = ToolsPlacement.resolve(
            pickerVisible: true, reported: .null, measured: [palette], window: window
        )
        XCTAssertEqual(placement, ToolsPlacement(obstructions: [palette], isUnknown: false))
    }

    func testOffScreenPaletteCopiesAreIgnored() {
        let parked = CGRect(x: 40, y: 1133, width: 664, height: 108.5)
        let placement = ToolsPlacement.resolve(
            pickerVisible: true, reported: .null, measured: [parked, palette], window: window
        )
        XCTAssertEqual(placement.obstructions, [palette])
    }

    func testVisiblePickerThatCannotBeFoundIsUnknown() {
        let placement = ToolsPlacement.resolve(
            pickerVisible: true, reported: .null, measured: [], window: window
        )
        XCTAssertTrue(placement.isUnknown)
    }

    func testHiddenPickerObstructsNothing() {
        let placement = ToolsPlacement.resolve(
            pickerVisible: false, reported: .null, measured: [], window: window
        )
        XCTAssertEqual(placement, ToolsPlacement(obstructions: [], isUnknown: false))
    }

    func testDefaultPaletteCropKeepsTheCanvasAbove() {
        let placement = ToolsPlacement.resolve(
            pickerVisible: true, reported: .null, measured: [palette], window: window
        )
        let layout = CanvasLayout(
            canvas: CGRect(x: 0, y: 74, width: 744, height: 1059),
            window: window.size,
            obstructions: placement.obstructions
        )
        XCTAssertEqual(
            CanvasCrop.shareableRect(of: layout),
            CGRect(x: 0, y: 74, width: 744, height: 930.5)
        )
    }
}
