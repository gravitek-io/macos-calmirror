import XCTest
@testable import CalmMirrorCore

/// Opt-in synthetic I/O benchmark. Run with:
/// `CALMIRROR_RUN_LOG_BENCHMARK=1 swift test -c release --filter SyncLogPerformanceBenchmarks`
final class SyncLogPerformanceBenchmarks: XCTestCase {
    func testRetainedHistoryReadPollAndAppendCosts() throws {
        guard ProcessInfo.processInfo.environment["CALMIRROR_RUN_LOG_BENCHMARK"] == "1" else {
            throw XCTSkip("Set CALMIRROR_RUN_LOG_BENCHMARK=1 to run synthetic I/O measurements.")
        }

        print("BENCH_ENV os=\(ProcessInfo.processInfo.operatingSystemVersionString) arch=arm64 samples=7 build=release")
        for count in [1_000, 17_000, 100_000] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CalMirrorLogBenchmark-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("sync-logs.json")
            let fixture = makeHistory(count: count)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(fixture).write(to: file, options: .atomic)
            let store = try SyncLogStore(logFileURL: file)
            let initialBytes = try fileSize(file)

            let load = try measure(samples: 7) { _ = try store.loadLogsChecked() }
            let pollDate = Date().addingTimeInterval(-60)
            let pollSnapshot = try store.loadLogsChecked(since: pollDate, ifChangedFrom: nil)
            let poll = try measure(samples: 7) {
                _ = try store.loadLogsChecked(since: pollDate, ifChangedFrom: pollSnapshot.revision)
            }
            let latest = try measure(samples: 7) { _ = try store.latestLogByRuleChecked() }
            let append = try measure(samples: 7) {
                try store.appendLog(SyncLog(ruleId: UUID(), timestamp: Date(), durationSeconds: 0,
                    added: [], removed: [], updated: [], errors: []))
            }
            let finalBytes = try fileSize(file)
            print(String(format: "BENCH_LOG count=%d initial_bytes=%d final_bytes=%d six_rule_rewrite_bytes_est=%d load_ms_p50=%.2f load_ms_p95=%.2f poll_ms_p50=%.2f poll_ms_p95=%.2f latest_ms_p50=%.2f latest_ms_p95=%.2f append_ms_p50=%.2f append_ms_p95=%.2f",
                count, initialBytes, finalBytes, initialBytes * 6,
                load.p50, load.p95, poll.p50, poll.p95, latest.p50, latest.p95,
                append.p50, append.p95))
        }
    }

    private func makeHistory(count: Int) -> [SyncLog] {
        let ruleID = UUID()
        let now = Date()
        return (0..<count).map { index in
            SyncLog(ruleId: ruleID,
                timestamp: now.addingTimeInterval(Double(index - count)),
                durationSeconds: 0.25, added: [], removed: [], updated: [], errors: [])
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func measure(samples: Int, operation: () throws -> Void) rethrows -> (p50: Double, p95: Double) {
        var durations: [Double] = []
        durations.reserveCapacity(samples)
        for _ in 0..<samples {
            let start = ProcessInfo.processInfo.systemUptime
            try operation()
            durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        durations.sort()
        let p50 = durations[(durations.count - 1) / 2]
        let p95 = durations[min(durations.count - 1, Int(ceil(Double(durations.count) * 0.95)) - 1)]
        return (p50, p95)
    }
}
