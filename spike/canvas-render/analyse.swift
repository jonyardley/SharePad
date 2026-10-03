#!/usr/bin/env swift

import Foundation

// Reduces one probe run (specs/canvas-render-spike.md §4) to the numbers the §5 pass
// bar needs. Pass the -frames.csv; the -seconds.csv beside it is read too. The first
// five seconds are dropped: the encoder's first session is slow to create.

let framesPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let secondsPath = framesPath.replacingOccurrences(of: "-frames.csv", with: "-seconds.csv")
let warmUp = 5.0

func rows(_ path: String) -> [[Double?]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("cannot read \(path)")
        exit(1)
    }
    let all = text.split(separator: "\n").dropFirst().map { line in
        line.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) }
    }
    guard let start = all.first?.first ?? nil else { return [] }
    return all.filter { ($0.first ?? nil).map { $0 - start >= warmUp } ?? false }
}

func column(_ rows: [[Double?]], _ index: Int) -> [Double] {
    rows.compactMap { $0.count > index ? $0[index] : nil }.sorted()
}

func percentile(_ sorted: [Double], _ p: Double) -> String {
    guard !sorted.isEmpty else { return "n/a" }
    let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
    return String(format: "%.2f", sorted[index])
}

func line(_ name: String, _ values: [Double]) {
    let label = name.padding(toLength: 14, withPad: " ", startingAt: 0)
    print(
        "\(label) median \(percentile(values, 0.5))  p95 \(percentile(values, 0.95))  max \(percentile(values, 1))"
    )
}

let frames = rows(framesPath)
let seconds = rows(secondsPath)
print("frames \(frames.count), seconds \(seconds.count)")
line("delivery_ms", column(frames, 1))
line("render_ms", column(frames, 2))
line("captured_fps", column(seconds, 1))
line("encoded_fps", column(seconds, 2))
line(
    "encode_ms",
    column(seconds.filter { ($0.count > 3 ? $0[3] : nil).map { $0 > 0 } ?? false }, 3)
)
line("cpu_pct", column(seconds, 6))
let battery = seconds.compactMap { $0.count > 7 ? $0[7] : nil }
if let first = battery.first, let last = battery.last {
    print(String(
        format: "battery        %.0f%% to %.0f%% over %.0f min",
        first * 100,
        last * 100,
        Double(seconds.count) / 60
    ))
}

print(
    "thermal max    \(column(seconds, 8).last.map { String(Int($0)) } ?? "n/a") (0 nominal, 1 fair, 2 serious, 3 critical)"
)
