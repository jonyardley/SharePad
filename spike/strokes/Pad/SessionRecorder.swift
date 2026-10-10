import PencilKit
import UIKit

// One JSON object per line in Documents/strokes-<time>.jsonl, read by
// spike/strokes/Render. Times are system uptime seconds, the clock UITouch uses.
final class SessionRecorder {
    private(set) var fileName = "no session"
    private var handle: FileHandle?
    private var directory: URL?

    func start(canvasSize: CGSize, scale: CGFloat) {
        guard handle == nil,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
              .first
        else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
            of: ":",
            with: "-"
        )
        let folder = documents.appendingPathComponent("session-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("strokes.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        directory = folder
        fileName = folder.lastPathComponent
        write([
            "t": "session",
            "device": UIDevice.current.model,
            "system": UIDevice.current.systemVersion,
            "canvas": [canvasSize.width, canvasSize.height],
            "scale": scale,
            "time": ProcessInfo.processInfo.systemUptime,
        ])
    }

    func strokeBegan(id: Int, tool: PKTool, touchType: String, time: TimeInterval) {
        write([
            "t": "begin",
            "id": id,
            "tool": Self.describe(tool),
            "touch": touchType,
            "time": time,
        ])
    }

    func points(id: Int, points: [[Double]]) {
        write(["t": "pts", "id": id, "p": points])
    }

    func strokeEnded(id: Int, time: TimeInterval, cancelled: Bool) {
        write(["t": "end", "id": id, "time": time, "cancelled": cancelled])
    }

    func drawingChanged(_ drawing: PKDrawing, visible: CGRect, zoom: CGFloat) {
        let data = drawing.dataRepresentation()
        write([
            "t": "drawing",
            "time": ProcessInfo.processInfo.systemUptime,
            "strokes": drawing.strokes.count,
            "bytes": data.count,
            "visible": Self.array(visible),
            "zoom": zoom,
            "data": data.base64EncodedString(),
        ])
    }

    func snapshot(index: Int, png: Data, drawing: PKDrawing, rect: CGRect, scale: CGFloat) {
        let name = "snap-\(index)-ipad.png"
        if let directory { try? png.write(to: directory.appendingPathComponent(name)) }
        write([
            "t": "snap",
            "n": index,
            "file": name,
            "time": ProcessInfo.processInfo.systemUptime,
            "rect": Self.array(rect),
            "scale": scale,
            "strokes": drawing.strokes.count,
            "data": drawing.dataRepresentation().base64EncodedString(),
        ])
    }

    private func write(_ object: [String: Any]) {
        guard let handle,
              var line = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        line.append(0x0A)
        handle.write(line)
    }

    private static func array(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height]
    }

    private static func describe(_ tool: PKTool) -> [String: Any] {
        switch tool {
        case let ink as PKInkingTool:
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [
                "kind": "ink",
                "ink": ink.inkType.rawValue,
                "color": [red, green, blue, alpha],
                "width": ink.width,
            ]
        case let eraser as PKEraserTool:
            return ["kind": "eraser", "eraser": eraser.eraserType == .bitmap ? "bitmap" : "vector"]
        case is PKLassoTool:
            return ["kind": "lasso"]
        default:
            return ["kind": String(describing: type(of: tool))]
        }
    }
}
