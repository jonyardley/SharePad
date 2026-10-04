import CoreGraphics
import PencilKit
@testable import SharePadPad
import UIKit
import XCTest

final class DrawingExportTests: XCTestCase {
    func testAnEmptyDrawingHasNothingToExport() {
        XCTAssertNil(DrawingExport(drawingBounds: .null))
        XCTAssertNil(DrawingExport(drawingBounds: .zero))
    }

    func testTheAreaIsTheDrawingPlusTheMargin() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: -300, y: 120, width: 400, height: 200
        )))
        let margin = DrawingExport.margin
        XCTAssertEqual(export.area, CGRect(
            x: -300 - margin, y: 120 - margin, width: 400 + margin * 2, height: 200 + margin * 2
        ))
    }

    func testTheAreaRoundsOutToWholePoints() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 10.4, y: 20.6, width: 99.3, height: 50.2
        )))
        XCTAssertEqual(export.area, export.area.integral)
        XCTAssertTrue(export.area.contains(CGRect(x: 10.4, y: 20.6, width: 99.3, height: 50.2)))
    }

    func testTheImageIsAtDoubleResolution() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 0, y: 0, width: 904, height: 404
        )))
        XCTAssertEqual(export.scale, 2)
        XCTAssertEqual(export.pixelSize, CGSize(width: 2000, height: 1000))
    }

    func testAHugeDrawingIsCappedInPixels() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 0, y: 0, width: 20000, height: 1000
        )))
        XCTAssertEqual(export.pixelSize.width, DrawingExport.maximumPixels, accuracy: 1)
    }

    func testThePdfPageIsTheSizeOfTheArea() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 0, y: 0, width: 1000, height: 600
        )))
        XCTAssertEqual(export.pageSize, export.area.size)
    }

    func testAHugePdfPageShrinksToTheLargestPageViewersOpen() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 0, y: 0, width: 30000, height: 3000
        )))
        XCTAssertEqual(export.pageSize.width, DrawingExport.maximumPage, accuracy: 0.001)
        XCTAssertEqual(
            export.pageSize.width / export.pageSize.height,
            export.area.width / export.area.height,
            accuracy: 0.001
        )
    }

    func testThePaperLinesUpWithTheBoard() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 100, y: 100, width: 200, height: 200
        )))
        let grid = PaperGrid(
            spacing: 32, minimumGap: 24, viewport: export.paperViewport, size: export.area.size
        )
        let first = try XCTUnwrap(grid.columns.first)
        XCTAssertEqual((export.area.minX + first).truncatingRemainder(dividingBy: 32), 0)
    }

    func testZoomedOutPaperThinsItsGrid() throws {
        let export = try XCTUnwrap(DrawingExport(drawingBounds: CGRect(
            x: 0, y: 0, width: 20000, height: 1000
        )))
        XCTAssertLessThan(export.paperZoom, 1)
        let size = CGSize(
            width: export.area.width * export.paperZoom,
            height: export.area.height * export.paperZoom
        )
        let grid = PaperGrid(
            spacing: 32, minimumGap: 24, viewport: export.paperViewport, size: size
        )
        let gaps = zip(grid.columns.dropFirst(), grid.columns).map { $0 - $1 }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(gaps.min()), 24 - 0.001)
    }

    func testTheFileNameCarriesTheDateAndFormat() throws {
        let date = Date(timeIntervalSince1970: 1_791_120_720)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(
            DrawingExport.fileName(for: .pdf, at: date, in: utc),
            "SharePad 2026-10-04 at 13.32.pdf"
        )
    }
}

@MainActor
final class DrawingExporterTests: XCTestCase {
    private let drawing: PKDrawing = {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 100)].enumerated()
            .map { index, location in
                PKStrokePoint(
                    location: location, timeOffset: TimeInterval(index), size: CGSize(
                        width: 4,
                        height: 4
                    ),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }()

    func testAnEmptyDrawingWritesNothing() throws {
        XCTAssertNil(try DrawingExporter.write(PKDrawing(), paper: Paper(), as: .png))
    }

    func testThePngIsTheWholeDrawingOnDarkPaper() throws {
        let url = try XCTUnwrap(DrawingExporter.write(
            drawing, paper: Paper(style: .grid, tone: .dark), as: .png
        ))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let export = try XCTUnwrap(DrawingExport(drawingBounds: drawing.bounds))
        XCTAssertEqual(CGSize(width: image.width, height: image.height), export.pixelSize)
        XCTAssertLessThan(try cornerBrightness(of: image), 0.2)
    }

    func testThePdfIsOnePageTheSizeOfTheDrawing() throws {
        let url = try XCTUnwrap(DrawingExporter.write(drawing, paper: Paper(), as: .pdf))
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 1)
        let export = try XCTUnwrap(DrawingExport(drawingBounds: drawing.bounds))
        XCTAssertEqual(pdf.page(at: 1)?.getBoxRect(.mediaBox).size, export.pageSize)
    }

    private func cornerBrightness(of image: CGImage) throws -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return CGFloat(pixel[0]) / 255
    }
}
