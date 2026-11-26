import AppKit
import Foundation
import PencilKit

// ── Session file ──

struct RawStroke {
    var id: Int
    var tool: [String: Any]
    var touch: String
    var begin: Double
    var end: Double?
    var cancelled = false
    var points: [[Double]] = []

    var isInk: Bool {
        tool["kind"] as? String == "ink"
    }

    var inkName: String {
        tool["ink"] as? String ?? (tool["kind"] as? String ?? "?")
    }

    var width: Double {
        tool["width"] as? Double ?? 0
    }
}

struct DrawingEvent {
    var time: Double
    var strokes: Int
    var bytes: Int
    var data: Data
}

struct Snap {
    var n: Int
    var file: String
    var time: Double
    var rect: CGRect
    var scale: Double
    var data: Data
}

struct Session {
    var strokes: [RawStroke] = []
    var drawings: [DrawingEvent] = []
    var snaps: [Snap] = []
    var system = "?"

    init(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var byID: [Int: Int] = [:]
        for line in text.split(separator: "\n") {
            guard let object = try? JSONSerialization
                .jsonObject(with: Data(line.utf8)) as? [String: Any],
                let kind = object["t"] as? String
            else { continue }
            switch kind {
            case "session":
                system = "\(object["device"] ?? "?") iPadOS \(object["system"] ?? "?")"
            case "begin":
                let id = object["id"] as? Int ?? 0
                byID[id] = strokes.count
                strokes.append(RawStroke(
                    id: id,
                    tool: object["tool"] as? [String: Any] ?? [:],
                    touch: object["touch"] as? String ?? "?",
                    begin: object["time"] as? Double ?? 0
                ))
            case "pts":
                if let index = byID[object["id"] as? Int ?? -1] {
                    strokes[index].points += object["p"] as? [[Double]] ?? []
                }
            case "end":
                if let index = byID[object["id"] as? Int ?? -1] {
                    strokes[index].end = object["time"] as? Double
                    strokes[index].cancelled = object["cancelled"] as? Bool ?? false
                }
            case "drawing":
                drawings.append(DrawingEvent(
                    time: object["time"] as? Double ?? 0,
                    strokes: object["strokes"] as? Int ?? 0,
                    bytes: object["bytes"] as? Int ?? 0,
                    data: Data(base64Encoded: object["data"] as? String ?? "") ?? Data()
                ))
            case "snap":
                let r = object["rect"] as? [Double] ?? [0, 0, 0, 0]
                snaps.append(Snap(
                    n: object["n"] as? Int ?? 0,
                    file: object["file"] as? String ?? "",
                    time: object["time"] as? Double ?? 0,
                    rect: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]),
                    scale: object["scale"] as? Double ?? 2,
                    data: Data(base64Encoded: object["data"] as? String ?? "") ?? Data()
                ))
            default:
                break
            }
        }
    }
}

// ── Pairing: the stroke PencilKit added for each pen-down ──

struct Pair {
    var raw: RawStroke
    var truth: PKStroke
    var liftToDrawingMs: Double
}

func pairStrokes(_ session: Session) -> [Pair] {
    var pairs: [Pair] = []
    for raw in session.strokes where raw.isInk && !raw.cancelled {
        guard let end = raw.end,
              let index = session.drawings.firstIndex(where: { $0.time >= end - 0.001 })
        else { continue }
        let previous = index > 0 ? session.drawings[index - 1].strokes : 0
        let event = session.drawings[index]
        guard event.strokes == previous + 1,
              let drawing = try? PKDrawing(data: event.data),
              let stroke = drawing.strokes.last
        else { continue }
        pairs.append(Pair(raw: raw, truth: stroke, liftToDrawingMs: (event.time - end) * 1000))
    }
    return pairs
}

// ── Width model: fitted from PencilKit's own points, per ink ──

struct WidthModel {
    var base: Double
    var perForce: Double
    var opacity: Double

    func size(width: Double, force: Double) -> Double {
        max(0.1, width * (base + perForce * force))
    }
}

func fitModels(_ pairs: [Pair]) -> [String: WidthModel] {
    var grouped: [String: [(force: Double, ratio: Double, opacity: Double)]] = [:]
    for pair in pairs where pair.raw.width > 0 {
        for point in pair.truth.path {
            grouped[pair.raw.inkName, default: []].append((
                Double(point.force),
                Double(point.size.width) / pair.raw.width,
                Double(point.opacity)
            ))
        }
    }
    var models: [String: WidthModel] = [:]
    for (ink, samples) in grouped where samples.count > 1 {
        let n = Double(samples.count)
        let meanX = samples.map(\.force).reduce(0, +) / n
        let meanY = samples.map(\.ratio).reduce(0, +) / n
        let sxx = samples.map { ($0.force - meanX) * ($0.force - meanX) }.reduce(0, +)
        let sxy = samples.map { ($0.force - meanX) * ($0.ratio - meanY) }.reduce(0, +)
        let slope = sxx > 1e-9 ? sxy / sxx : 0
        models[ink] = WidthModel(
            base: meanY - slope * meanX,
            perForce: slope,
            opacity: samples.map(\.opacity).reduce(0, +) / n
        )
    }
    return models
}

// Pencil, watercolour and crayon texture comes from the stroke's random seed, so the
// rebuild borrows PencilKit's; on the wire the seed would ride with the stroke end.
func rebuild(_ raw: RawStroke, model: WidthModel?, seed: UInt32?) -> PKStroke? {
    guard let first = raw.points.first,
          let inkName = raw.tool["ink"] as? String,
          let inkType = PKInk.InkType(rawValue: inkName)
    else { return nil }
    let rgba = raw.tool["color"] as? [Double] ?? [0, 0, 0, 1]
    let color = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    let ink = PKInk(inkType, color: color)
    let model = model ?? WidthModel(base: 1, perForce: 0, opacity: 1)
    let points = raw.points.map { p -> PKStrokePoint in
        let force = p[4] > 0 ? p[3] / p[4] * 4.0 / 3.0 : 1
        let size = model.size(width: raw.width, force: force)
        return PKStrokePoint(
            location: CGPoint(x: p[0], y: p[1]),
            timeOffset: p[2] - first[2],
            size: CGSize(width: size, height: size),
            opacity: model.opacity,
            force: force,
            azimuth: p[5],
            altitude: p[6]
        )
    }
    var stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
    if let seed { stroke.randomSeed = seed }
    return stroke
}

// ── Rendering and pixel diff ──

func render(_ drawing: PKDrawing, rect: CGRect, scale: Double) -> CGImage? {
    var image: NSImage?
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        image = drawing.image(from: rect, scale: scale)
    }
    return image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 255, count: width * height * 4)
    buffer.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return buffer
}

struct Diff {
    var inkPixels = 0
    var differing = 0
    var percent: Double {
        inkPixels == 0 ? 0 : Double(differing) / Double(inkPixels) * 100
    }
}

func diff(_ a: CGImage, _ b: CGImage, writeTo url: URL) -> Diff {
    let width = a.width, height = a.height
    let pa = pixels(a, width: width, height: height)
    let pb = pixels(b, width: width, height: height)
    var out = [UInt8](repeating: 255, count: width * height * 4)
    var result = Diff()
    for i in stride(from: 0, to: pa.count, by: 4) {
        let inkA = pa[i] < 240 || pa[i + 1] < 240 || pa[i + 2] < 240
        let inkB = pb[i] < 240 || pb[i + 1] < 240 || pb[i + 2] < 240
        guard inkA || inkB else { continue }
        result.inkPixels += 1
        let delta = (0 ..< 3).map { abs(Int(pa[i + $0]) - Int(pb[i + $0])) }.max() ?? 0
        if delta > 48 {
            result.differing += 1
            out[i] = 230; out[i + 1] = 30; out[i + 2] = 30
        } else {
            out[i] = 200; out[i + 1] = 200; out[i + 2] = 200
        }
    }
    writePNG(out, width: width, height: height, to: url)
    return result
}

func writePNG(_ bytes: [UInt8], width: Int, height: Int, to url: URL) {
    var bytes = bytes
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return }
        writePNG(image, to: url)
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func loadPNG(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// ── Report ──

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
}

func f1(_ value: Double) -> String {
    String(format: "%.1f", value)
}

func analyse(sessionDir: URL, out: URL) throws {
    let session = try Session(url: sessionDir.appendingPathComponent("strokes.jsonl"))
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var report = "# Stroke spike report: \(sessionDir.lastPathComponent)\n\n\(session.system), rendered on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"

    // Live: does PencilKit hand over anything while the pen is down?
    let finished = session.strokes.filter { !$0.cancelled && $0.end != nil }
    let duringPenDown = finished.filter { stroke in
        session.drawings.contains { $0.time > stroke.begin && $0.time < (stroke.end ?? 0) - 0.001 }
    }
    let pairs = pairStrokes(session)
    let lift = pairs.map(\.liftToDrawingMs)
    report += "## Live strokes\n\n"
    report += "- Pen-downs recorded: \(session.strokes.count) (\(finished.count) finished, \(session.strokes.filter(\.cancelled).count) cancelled)\n"
    report += "- Drawing changes that arrived while a pen was still down: \(duringPenDown.count)\n"
    report += "- Pen lift to PencilKit's drawing change: median \(f1(percentile(lift, 0.5))) ms, p95 \(f1(percentile(lift, 0.95))) ms\n\n"

    // Cost: raw points as they'd go on the wire, against whole-drawing snapshots.
    let rates = finished.compactMap { stroke -> Double? in
        guard let end = stroke.end, end - stroke.begin > 0.05 else { return nil }
        return Double(stroke.points.count) / (end - stroke.begin)
    }
    let pointsPerSecond = percentile(rates, 0.5)
    report += "## Cost\n\n"
    report += "- Points per second while drawing: median \(f1(pointsPerSecond)), p95 \(f1(percentile(rates, 0.95)))\n"
    report += "- At 10 bytes a point: about \(f1(pointsPerSecond * 10 * 8 / 1000)) kbps while the pen moves\n"
    if let biggest = session.drawings.map(\.bytes).max(), let last = session.drawings.last {
        report += "- Whole-drawing snapshot: \(last.bytes) bytes at \(last.strokes) strokes, largest \(biggest) bytes\n"
    }
    report += "\n"

    // Width model.
    let models = fitModels(pairs)
    report += "## Width model (fitted from PencilKit's own points)\n\n| Ink | Paired strokes | Raw points (median) | PencilKit points (median) | size ÷ width = a + b × force | Opacity |\n|---|---|---|---|---|---|\n"
    for ink in Set(pairs.map(\.raw.inkName)).sorted() {
        let group = pairs.filter { $0.raw.inkName == ink }
        let rawCount = percentile(group.map { Double($0.raw.points.count) }, 0.5)
        let truthCount = percentile(group.map { Double($0.truth.path.count) }, 0.5)
        let model = models[ink]
        let fit = model
            .map {
                "\(String(format: "%.3f", $0.base)) + \(String(format: "%.3f", $0.perForce)) × f"
            } ?? "n/a"
        report += "| \(ink) | \(group.count) | \(Int(rawCount)) | \(Int(truthCount)) | \(fit) | \(model.map { String(format: "%.2f", $0.opacity) } ?? "n/a") |\n"
    }
    report += "\n"

    // Snapshots.
    report += "## Snapshots\n\n| Snap | Strokes | iPad vs Mac (same drawing) | PencilKit vs rebuilt from live points | Rebuilt valid |\n|---|---|---|---|---|\n"
    for snap in session.snaps {
        guard let drawing = try? PKDrawing(data: snap.data),
              let ipad = loadPNG(sessionDir.appendingPathComponent(snap.file)),
              let mac = render(drawing, rect: snap.rect, scale: snap.scale)
        else {
            report += "| \(snap.n) | ? | could not load | | |\n"
            continue
        }
        let prefix = "snap-\(snap.n)"
        writePNG(ipad, to: out.appendingPathComponent("\(prefix)-ipad.png"))
        writePNG(mac, to: out.appendingPathComponent("\(prefix)-mac.png"))
        let macDiff = diff(
            ipad,
            mac,
            writeTo: out.appendingPathComponent("\(prefix)-diff-ipad-vs-mac.png")
        )

        let before = pairs.filter { ($0.raw.end ?? .infinity) <= snap.time }
        let valid = before.count == drawing.strokes.count
            && session.strokes.filter { !$0.isInk && $0.begin < snap.time }.isEmpty
        var rebuiltCell = "n/a"
        let rebuilt = PKDrawing(strokes: before.compactMap { rebuild(
            $0.raw,
            model: models[$0.raw.inkName],
            seed: $0.truth.randomSeed
        ) })
        if let rebuiltImage = render(rebuilt, rect: snap.rect, scale: snap.scale) {
            writePNG(rebuiltImage, to: out.appendingPathComponent("\(prefix)-rebuilt.png"))
            let d = diff(
                mac,
                rebuiltImage,
                writeTo: out.appendingPathComponent("\(prefix)-diff-pencilkit-vs-rebuilt.png")
            )
            rebuiltCell = "\(f1(d.percent))% of ink pixels differ"
        }
        report += "| \(snap.n) | \(drawing.strokes.count) | \(f1(macDiff.percent))% of ink pixels differ | \(rebuiltCell) | \(valid ? "yes" : "no: eraser, lasso, undo or unpaired strokes before it") |\n"
    }

    try report.write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    print(report)
    print("Images and report in \(out.path)")
}

// ── Self-test: every ink renders on this Mac ──

func selfTest(out: URL) throws {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let inks: [PKInk.InkType] = [
        .pen,
        .pencil,
        .marker,
        .monoline,
        .fountainPen,
        .watercolor,
        .crayon,
    ]
    var strokes: [PKStroke] = []
    for (row, ink) in inks.enumerated() {
        let y = 40.0 + Double(row) * 50
        let points = (0 ... 60).map { i -> PKStrokePoint in
            let x = 30.0 + Double(i) * 6
            let force = 0.3 + Double(i) / 60
            return PKStrokePoint(
                location: CGPoint(x: x, y: y + sin(Double(i) / 6) * 12),
                timeOffset: Double(i) / 120,
                size: CGSize(width: 6 * force, height: 6 * force),
                opacity: 1, force: force, azimuth: 0, altitude: .pi / 3
            )
        }
        strokes.append(PKStroke(
            ink: PKInk(ink, color: .systemBlue),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        ))
    }
    let drawing = PKDrawing(strokes: strokes)
    let rect = CGRect(x: 0, y: 0, width: 440, height: 400)
    guard let image = render(drawing, rect: rect, scale: 2) else {
        print("FAIL: PencilKit returned no image")
        exit(1)
    }
    writePNG(image, to: out.appendingPathComponent("selftest-inks.png"))
    let px = pixels(image, width: image.width, height: image.height)
    var failed = false
    for (row, ink) in inks.enumerated() {
        let top = Int((20.0 + Double(row) * 50) * 2), bottom = Int((60.0 + Double(row) * 50) * 2)
        var count = 0
        for y in top ..< bottom {
            for x in 0 ..< image.width {
                let i = (y * image.width + x) * 4
                if px[i] < 240 || px[i + 1] < 240 || px[i + 2] < 240 { count += 1 }
            }
        }
        print("\(ink.rawValue): \(count) ink pixels")
        if count == 0 { failed = true }
    }
    let roundTrip = try PKDrawing(data: drawing.dataRepresentation())
    print(
        "Round trip: \(roundTrip.strokes.count) of \(strokes.count) strokes, \(drawing.dataRepresentation().count) bytes"
    )
    print(failed ? "FAIL: an ink drew nothing" : "OK: every ink drew on this Mac")
    if failed { exit(1) }
    try fakeSession(
        strokes: strokes,
        rect: rect,
        image: image,
        out: out.appendingPathComponent("fake-session")
    )
}

// A session file shaped like the iPad's, so the analysis runs end to end with no
// iPad. PencilKit's strokes are the self-test strokes; the "live" points are
// the same points, so every diff should come out at or near zero.
func fakeSession(strokes: [PKStroke], rect: CGRect, image: CGImage, out: URL) throws {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var lines: [[String: Any]] = [[
        "t": "session",
        "device": "fake",
        "system": "0",
        "canvas": [440, 400],
        "scale": 2,
        "time": 0,
    ]]
    var clock = 1.0
    var drawing = PKDrawing()
    for (index, stroke) in strokes.enumerated() {
        let id = index + 1
        lines.append(["t": "begin", "id": id, "touch": "pencil", "time": clock, "tool": [
            "kind": "ink", "ink": stroke.ink.inkType.rawValue, "color": [0.0, 0.48, 1.0, 1.0],
            "width": 6.0,
        ]])
        let points = stroke.path.map { p in
            [
                Double(p.location.x),
                Double(p.location.y),
                clock + p.timeOffset,
                Double(p.force) * 3 / 4,
                1.0,
                Double(p.azimuth),
                Double(p.altitude),
            ]
        }
        lines.append(["t": "pts", "id": id, "p": points])
        clock += 0.6
        lines.append(["t": "end", "id": id, "time": clock, "cancelled": false])
        drawing.strokes.append(stroke)
        clock += 0.02
        let data = drawing.dataRepresentation()
        lines.append([
            "t": "drawing",
            "time": clock,
            "strokes": drawing.strokes.count,
            "bytes": data.count,
            "visible": [0, 0, 440, 400],
            "zoom": 1,
            "data": data.base64EncodedString(),
        ])
        clock += 0.3
    }
    writePNG(image, to: out.appendingPathComponent("snap-1-ipad.png"))
    lines.append([
        "t": "snap",
        "n": 1,
        "file": "snap-1-ipad.png",
        "time": clock,
        "rect": [0, 0, rect.width, rect.height],
        "scale": 2,
        "strokes": drawing.strokes.count,
        "data": drawing.dataRepresentation().base64EncodedString(),
    ])
    let text = try lines.map { try String(
        decoding: JSONSerialization.data(withJSONObject: $0),
        as: UTF8.self
    ) }
    .joined(separator: "\n")
    try text.write(
        to: out.appendingPathComponent("strokes.jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try analyse(sessionDir: out, out: out.appendingPathComponent("mac"))
}

// ── Entry ──

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--selftest" {
    try selfTest(out: URL(fileURLWithPath: args[2]))
} else if args.count >= 2 {
    let dir = URL(fileURLWithPath: args[1])
    let out = args.count >= 4 && args[2] == "--out" ? URL(fileURLWithPath: args[3]) : dir
        .appendingPathComponent("mac")
    try analyse(sessionDir: dir, out: out)
} else {
    print("usage: stroke-render <session-dir> [--out <dir>] | stroke-render --selftest <dir>")
    exit(2)
}
