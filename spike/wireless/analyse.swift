#!/usr/bin/env swift

import Foundation

// Reduces a spike-receiver CSV to the numbers specs/wireless.md's go/kill call
// needs. The first two seconds are discarded: the encoder's first session costs
// ~1.8 s to create and those frames say nothing about steady-state latency.

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/spike-latency.csv"
guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
    print("cannot read \(path)")
    exit(1)
}

struct Row {
    let wall: Double
    let latency: Double
    let decode: Double
    let interval: Double
    let bytes: Int
    let keyframe: Bool
}

let rows: [Row] = contents
    .split(separator: "\n")
    .dropFirst()
    .compactMap { line in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 7,
              let wall = Double(fields[1]),
              let latency = Double(fields[2]),
              let decode = Double(fields[3]),
              let interval = Double(fields[4]),
              let bytes = Int(fields[5])
        else { return nil }
        return Row(
            wall: wall,
            latency: latency,
            decode: decode,
            interval: interval,
            bytes: bytes,
            keyframe: fields[6] == "1"
        )
    }

guard let first = rows.first else {
    print("no rows in \(path)")
    exit(1)
}

let warmupCutoff = first.wall + 2
let steady = rows.filter { $0.wall >= warmupCutoff }
guard !steady.isEmpty else {
    print("only \(rows.count) rows, all inside the 2 s warm-up window")
    exit(1)
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    let index = Int((Double(sorted.count - 1) * fraction).rounded())
    return sorted[index]
}

func medianAbsoluteDeviation(_ values: [Double]) -> Double {
    let median = percentile(values, 0.5)
    return percentile(values.map { abs($0 - median) }, 0.5)
}

func summarise(_ label: String, _ values: [Double], unit: String = "ms") {
    guard !values.isEmpty else { return }
    print(String(
        format: "%-22@ med %7.1f  p95 %7.1f  min %7.1f  max %7.1f  jitter ±%.1f %@",
        label as NSString,
        percentile(values, 0.5),
        percentile(values, 0.95),
        values.min() ?? 0,
        values.max() ?? 0,
        medianAbsoluteDeviation(values),
        unit as NSString
    ))
}

let span = (steady.last?.wall ?? 0) - (steady.first?.wall ?? 0)
let bitrate = Double(steady.reduce(0) { $0 + $1.bytes }) * 8 / max(span, 0.001) / 1000

print(
    "\(path): \(rows.count) frames, \(steady.count) after warm-up, \(String(format: "%.1f", span)) s"
)
print(String(format: "rate                   %.1f fps, %.0f kbps, %d keyframes",
             Double(steady.count) / max(span, 0.001), bitrate, steady.filter(\.keyframe).count))
summarise("capture→decoded", steady.map(\.latency))
summarise("decode", steady.map(\.decode))
summarise("frame interval", steady.filter { $0.interval > 0 }.map(\.interval))

let median = percentile(steady.map(\.latency), 0.5)
print("")
print("GO/KILL reference (specs/wireless.md): GO needs a glass-to-glass median")
print(
    "under ~120 ms with low jitter. capture→decoded here is \(String(format: "%.0f", median)) ms, which"
)
print("EXCLUDES iPad touch-to-display and Mac present time. The camera measurement")
print("is the number that decides it.")
