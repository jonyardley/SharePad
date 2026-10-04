import PencilKit
import SwiftUI
import UIKit

enum DrawingExportError: Error {
    case paperDidNotRender
}

@MainActor
enum DrawingExporter {
    static func write(
        _ drawing: PKDrawing,
        paper: Paper,
        as format: ExportFormat,
        at date: Date = Date()
    ) throws -> URL? {
        guard let export = DrawingExport(drawingBounds: drawing.bounds) else { return nil }
        let backdrop = try paperImage(paper, export: export)
        let ink = inkImage(drawing, tone: paper.tone, export: export)
        let area = CGRect(origin: .zero, size: export.area.size)
        let data = switch format {
        case .png:
            pngData(export: export) { _ in
                backdrop.draw(in: area)
                ink.draw(in: area)
            }
        case .pdf:
            pdfData(export: export) { context in
                context.scaleBy(
                    x: export.pageSize.width / area.width,
                    y: export.pageSize.height / area.height
                )
                backdrop.draw(in: area)
                ink.draw(in: area)
            }
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: DrawingExport.fileName(for: format, at: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func paperImage(_ paper: Paper, export: DrawingExport) throws -> UIImage {
        let renderer = ImageRenderer(
            content: PaperBackground(paper: paper, viewport: export.paperViewport)
                .frame(width: export.area.width, height: export.area.height)
        )
        renderer.scale = export.scale
        guard let image = renderer.uiImage else { throw DrawingExportError.paperDidNotRender }
        return image
    }

    // PencilKit draws ink for the current trait collection, so dark paper needs the
    // dark variants the canvas showed (PKDrawing.image(from:scale:) docs).
    private static func inkImage(_ drawing: PKDrawing, tone: PaperTone,
                                 export: DrawingExport) -> UIImage {
        let style: UIUserInterfaceStyle = tone == .dark ? .dark : .light
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
            image = drawing.image(from: export.area, scale: export.scale)
        }
        return image
    }

    private static func pngData(
        export: DrawingExport,
        draw: (CGContext) -> Void
    ) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = export.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: export.area.size, format: format)
        return renderer.pngData { draw($0.cgContext) }
    }

    private static func pdfData(
        export: DrawingExport,
        draw: (CGContext) -> Void
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: export.pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            draw(context.cgContext)
        }
    }
}
