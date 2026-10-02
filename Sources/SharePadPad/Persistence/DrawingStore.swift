import Foundation
import os
import PencilKit

struct DrawingStore {
    private let url: URL
    private let log = Logger(subsystem: "co.sharepad.ipad", category: "drawing")

    init(directory: URL) {
        url = directory.appendingPathComponent("drawing.pkdrawing")
    }

    static func applicationSupport() -> DrawingStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return DrawingStore(directory: base.appendingPathComponent("SharePad", isDirectory: true))
    }

    func load() -> PKDrawing {
        guard let data = try? Data(contentsOf: url) else { return PKDrawing() }
        do {
            return try PKDrawing(data: data)
        } catch {
            log.error("unreadable drawing, starting blank: \(error.localizedDescription)")
            return PKDrawing()
        }
    }

    func save(_ drawing: PKDrawing) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try drawing.dataRepresentation().write(to: url, options: .atomic)
    }
}
