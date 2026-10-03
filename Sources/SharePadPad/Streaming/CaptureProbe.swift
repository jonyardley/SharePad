#if DEBUG
    import CoreMedia
    import Foundation
    import os
    import SharePadWire
    import UIKit

    final class CaptureProbe: Sendable {
        private struct Counters {
            var captured = 0
            var pendingRender: Double?
        }

        private let counters = OSAllocatedUnfairLock(initialState: Counters())
        private let writer = DispatchQueue(label: "co.sharepad.ipad.probe")
        private let frames: FileHandle
        private let seconds: FileHandle

        init?(source: String) {
            guard let folder = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
            let stamp = Date()
                .formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "")
            let base = "probe-\(source)-\(stamp)"
            guard let frames = Self.open(folder.appending(path: "\(base)-frames.csv"),
                                         header: "uptime,delivery_ms,render_ms"),
                let seconds = Self.open(
                    folder.appending(path: "\(base)-seconds.csv"),
                    header: "uptime,captured_fps,encoded_fps,encode_ms,kbps,skipped,"
                        + "cpu_pct,battery,thermal"
                )
            else { return nil }
            self.frames = frames
            self.seconds = seconds
        }

        func rendered(_ milliseconds: Double) {
            counters.withLock { $0.pendingRender = milliseconds }
        }

        func captured(_ frame: CapturedFrame) {
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let delivery = (now - frame.presentationTime).seconds * 1000
            let render = counters.withLock { counters in
                counters.captured += 1
                defer { counters.pendingRender = nil }
                return counters.pendingRender
            }
            let line = String(
                format: "%.3f,%.2f,%@\n",
                ProcessInfo.processInfo.systemUptime,
                delivery,
                render.map { String(format: "%.2f", $0) } ?? ""
            )
            write(line, to: frames)
        }

        func takeCaptured() -> Int {
            counters.withLock { counters in
                defer { counters.captured = 0 }
                return counters.captured
            }
        }

        func second(_ row: String) {
            write(row, to: seconds)
        }

        private func write(_ line: String, to handle: FileHandle) {
            writer.async { handle.write(Data(line.utf8)) }
        }

        private static func open(_ url: URL, header: String) -> FileHandle? {
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: Data("\(header)\n".utf8)
            ),
                let handle = try? FileHandle(forWritingTo: url) else { return nil }
            handle.seekToEndOfFile()
            return handle
        }
    }

    @MainActor
    final class ProbeSampler {
        private let probe: CaptureProbe
        private var timer: Timer?
        private var stats: StreamSender.Stats?
        private var lastCPU: (cpu: Double, wall: Double)?

        init(probe: CaptureProbe) {
            self.probe = probe
            UIDevice.current.isBatteryMonitoringEnabled = true
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func linkStats(_ stats: StreamSender.Stats) {
            self.stats = stats
        }

        private func sample() {
            let captured = probe.takeCaptured()
            // StreamSender reports on its own window and only after an encoded frame,
            // so a sample with no fresh report leaves the link columns empty.
            let fresh = stats
            stats = nil
            func field(_ value: Double?, _ format: String) -> String {
                value.map { String(format: format, $0) } ?? ""
            }
            let now = ProcessInfo.processInfo.systemUptime
            let cpu = Self.processCPUSeconds()
            let cpuPercent = lastCPU.map { (cpu - $0.cpu) / (now - $0.wall) * 100 } ?? 0
            lastCPU = (cpu, now)
            probe.second(String(
                format: "%.3f,%d,%@,%@,%@,%@,%.1f,%.2f,%d\n",
                now,
                captured,
                field(fresh?.framesPerSecond, "%.1f"),
                field(fresh?.encodeMilliseconds, "%.2f"),
                field(fresh?.kilobitsPerSecond, "%.0f"),
                field(fresh.map { Double($0.skippedFrames) }, "%.0f"),
                cpuPercent,
                UIDevice.current.batteryLevel,
                ProcessInfo.processInfo.thermalState.rawValue
            ))
        }

        private static func processCPUSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            func seconds(_ time: timeval) -> Double {
                Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
            }
            return seconds(usage.ru_utime) + seconds(usage.ru_stime)
        }
    }
#endif
