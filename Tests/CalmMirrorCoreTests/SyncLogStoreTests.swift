import XCTest
@testable import CalmMirrorCore

/// Unit tests for `SyncLogStore` covering read/write operations,
/// rule-based filtering, last-N retrieval, and retention pruning.
///
/// Each test creates a fresh temporary directory so tests are fully
/// isolated from each other and from the production log file.
final class SyncLogStoreTests: XCTestCase {

    // MARK: - Properties

    /// Temporary directory created per test; removed in `tearDown`.
    private var tempDirectory: URL!

    /// Store instance pointing at the temporary log file.
    private var store: SyncLogStore!

    // MARK: - Set Up / Tear Down

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncLogStoreTests-\(UUID().uuidString)", isDirectory: true)

        let logFileURL = tempDirectory.appendingPathComponent("sync-logs.json")
        store = try SyncLogStore(logFileURL: logFileURL)
    }

    override func tearDownWithError() throws {
        // Remove the entire temporary directory tree.
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        store = nil
        tempDirectory = nil

        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates a `SyncLog` with sensible defaults for testing.
    ///
    /// Only `ruleId` and `timestamp` are typically varied across tests;
    /// change arrays default to empty and duration to a short value.
    ///
    /// - Parameters:
    ///   - ruleId: The mirror rule identifier. Defaults to a random UUID.
    ///   - timestamp: The log timestamp. Defaults to now.
    /// - Returns: A fully initialised `SyncLog` ready for persistence.
    private func makeSyncLog(
        ruleId: UUID = UUID(),
        timestamp: Date = Date()
    ) -> SyncLog {
        SyncLog(
            ruleId: ruleId,
            timestamp: timestamp,
            durationSeconds: 0.5,
            added: [],
            removed: [],
            updated: [],
            errors: []
        )
    }

    /// Returns a `Date` offset from now by the given number of days.
    ///
    /// Negative values produce dates in the past.
    private func dateByAddingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())!
    }

    // MARK: - Tests

    /// A freshly created store with no prior writes returns an empty array.
    func testLoadLogsEmptyByDefault() {
        let logs = store.loadLogs()
        XCTAssertTrue(logs.isEmpty, "A new store should contain no logs")
    }

    /// Appending a single log and loading it back should return that exact entry.
    func testAppendAndLoad() throws {
        let ruleId = UUID()
        let log = makeSyncLog(ruleId: ruleId)

        try store.appendLog(log)
        let loaded = store.loadLogs()

        XCTAssertEqual(loaded.count, 1, "Store should contain exactly one log")
        XCTAssertEqual(loaded.first?.id, log.id, "Loaded log ID should match appended log")
        XCTAssertEqual(loaded.first?.ruleId, ruleId, "Loaded log ruleId should match")
        XCTAssertEqual(loaded.first!.durationSeconds, 0.5, accuracy: 0.001)
    }

    /// Appending three logs should return all three in insertion order.
    func testAppendMultipleLogs() throws {
        let log1 = makeSyncLog()
        let log2 = makeSyncLog()
        let log3 = makeSyncLog()

        try store.appendLog(log1)
        try store.appendLog(log2)
        try store.appendLog(log3)

        let loaded = store.loadLogs()

        XCTAssertEqual(loaded.count, 3, "Store should contain three logs")
        XCTAssertEqual(loaded[0].id, log1.id, "First log should be the earliest appended")
        XCTAssertEqual(loaded[1].id, log2.id, "Second log should match insertion order")
        XCTAssertEqual(loaded[2].id, log3.id, "Third log should be the latest appended")
    }

    /// Filtering by ruleId should return only logs for that rule.
    func testLoadLogsByRuleId() throws {
        let ruleA = UUID()
        let ruleB = UUID()

        try store.appendLog(makeSyncLog(ruleId: ruleA))
        try store.appendLog(makeSyncLog(ruleId: ruleB))
        try store.appendLog(makeSyncLog(ruleId: ruleA))

        let logsA = store.loadLogs(for: ruleA)
        let logsB = store.loadLogs(for: ruleB)

        XCTAssertEqual(logsA.count, 2, "Should return two logs for rule A")
        XCTAssertTrue(logsA.allSatisfy { $0.ruleId == ruleA }, "All returned logs should belong to rule A")
        XCTAssertEqual(logsB.count, 1, "Should return one log for rule B")
        XCTAssertEqual(logsB.first?.ruleId, ruleB)
    }

    /// `loadLogs(last:)` should return only the N most recent entries.
    func testLoadLogsLastN() throws {
        var allLogs: [SyncLog] = []
        for _ in 0..<5 {
            let log = makeSyncLog()
            try store.appendLog(log)
            allLogs.append(log)
        }

        let lastThree = store.loadLogs(last: 3)

        XCTAssertEqual(lastThree.count, 3, "Should return exactly 3 logs")
        XCTAssertEqual(lastThree[0].id, allLogs[2].id, "First of last-3 should be the third appended log")
        XCTAssertEqual(lastThree[1].id, allLogs[3].id)
        XCTAssertEqual(lastThree[2].id, allLogs[4].id, "Last of last-3 should be the most recent log")
    }

    /// Calling `pruneOldEntries()` should remove logs older than 30 days
    /// and keep recent ones.
    func testPruneOldEntries() throws {
        let oldLog = makeSyncLog(timestamp: dateByAddingDays(-31))
        let recentLog = makeSyncLog(timestamp: Date())

        // Write both logs directly (old then recent).
        try store.appendLog(recentLog)
        // To include the old log without it being auto-pruned on append,
        // we load, inject, and rewrite manually via two appends in sequence:
        // Actually, appendLog auto-prunes, so the old log would be pruned
        // on the second append. Instead, write them via separate store instance
        // that bypasses pruning? No — we test pruneOldEntries by writing the
        // raw file directly.
        //
        // Strategy: write the JSON file manually with both entries, then prune.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode([oldLog, recentLog])
        let logFileURL = tempDirectory.appendingPathComponent("sync-logs.json")
        try data.write(to: logFileURL, options: .atomic)

        // Verify both are present before pruning.
        let beforePrune = store.loadLogs()
        XCTAssertEqual(beforePrune.count, 2, "Both logs should be present before pruning")

        try store.pruneOldEntries()

        let afterPrune = store.loadLogs()
        XCTAssertEqual(afterPrune.count, 1, "Only the recent log should remain after pruning")
        XCTAssertEqual(afterPrune.first?.id, recentLog.id, "The surviving log should be the recent one")
    }

    /// `appendLog` auto-prunes old entries. Appending a new log when an old
    /// one already exists on disk should discard the old entry.
    func testAppendAutoPrunes() throws {
        let oldLog = makeSyncLog(timestamp: dateByAddingDays(-31))

        // Write the old log directly to the file so it is not pruned yet.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let logFileURL = tempDirectory.appendingPathComponent("sync-logs.json")
        let data = try encoder.encode([oldLog])
        try data.write(to: logFileURL, options: .atomic)

        // Verify the old log is on disk.
        XCTAssertEqual(store.loadLogs().count, 1, "Old log should be present before append")

        // Appending a new log triggers auto-prune inside appendLog.
        let newLog = makeSyncLog(timestamp: Date())
        try store.appendLog(newLog)

        let loaded = store.loadLogs()
        XCTAssertEqual(loaded.count, 1, "Only the new log should remain after auto-prune")
        XCTAssertEqual(loaded.first?.id, newLog.id, "The surviving log should be the newly appended one")
    }

    /// A log just inside the 30-day retention window should NOT be pruned.
    /// A log 31 days old should be pruned.
    func testRetentionBoundary() throws {
        // Use a 10-second buffer to avoid race conditions between test setup
        // and prune execution, both of which call Date() independently.
        let justInside30 = makeSyncLog(
            timestamp: dateByAddingDays(-SyncLogStore.retentionDays).addingTimeInterval(10)
        )
        let exactly31 = makeSyncLog(timestamp: dateByAddingDays(-(SyncLogStore.retentionDays + 1)))

        // Write both logs directly to bypass auto-prune on append.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let logFileURL = tempDirectory.appendingPathComponent("sync-logs.json")
        let data = try encoder.encode([exactly31, justInside30])
        try data.write(to: logFileURL, options: .atomic)

        XCTAssertEqual(store.loadLogs().count, 2, "Both logs should be on disk before pruning")

        try store.pruneOldEntries()

        let remaining = store.loadLogs()
        XCTAssertEqual(remaining.count, 1, "Only the 30-day-old log should survive pruning")
        XCTAssertEqual(
            remaining.first?.id,
            justInside30.id,
            "The log exactly at the retention boundary should be kept"
        )
    }
    // MARK: - Logs Since a Date

    /// `loadLogs(since:)` returns only entries whose timestamp is at or after
    /// the given date, in stored order. Used by the app to find the results
    /// of a sync it triggered.
    func testLoadLogsSinceReturnsOnlyNewerEntries() throws {
        let trigger = Date()
        let before = makeSyncLog(timestamp: trigger.addingTimeInterval(-60))
        let atTrigger = makeSyncLog(timestamp: trigger)
        let after = makeSyncLog(timestamp: trigger.addingTimeInterval(5))

        try store.appendLog(before)
        try store.appendLog(atTrigger)
        try store.appendLog(after)

        let recent = store.loadLogs(since: trigger)

        XCTAssertEqual(recent.map(\.id), [atTrigger.id, after.id],
                       "Only logs at or after the trigger date should be returned, in order")
    }

    /// `loadLogs(since:)` on an empty store returns an empty array.
    func testLoadLogsSinceEmptyStore() {
        XCTAssertTrue(store.loadLogs(since: Date()).isEmpty)
    }

    // MARK: - Latest Log Per Rule

    /// `latestLogByRule()` keeps the most recent entry for every rule, even
    /// when the file is not in chronological order.
    func testLatestLogByRuleKeepsMostRecentEntry() throws {
        let ruleA = UUID()
        let ruleB = UUID()
        let now = Date()

        let oldA = makeSyncLog(ruleId: ruleA, timestamp: now.addingTimeInterval(-300))
        let newA = makeSyncLog(ruleId: ruleA, timestamp: now)
        let onlyB = makeSyncLog(ruleId: ruleB, timestamp: now.addingTimeInterval(-100))

        // Append the newer entry first to prove ordering does not matter.
        try store.appendLog(newA)
        try store.appendLog(oldA)
        try store.appendLog(onlyB)

        let latest = store.latestLogByRule()

        XCTAssertEqual(latest.count, 2, "One entry per rule is expected")
        XCTAssertEqual(latest[ruleA]?.id, newA.id, "Rule A should map to its most recent log")
        XCTAssertEqual(latest[ruleB]?.id, onlyB.id, "Rule B should map to its only log")
    }

    /// `latestLogByRule()` on an empty store returns an empty dictionary.
    func testLatestLogByRuleEmptyStore() {
        XCTAssertTrue(store.latestLogByRule().isEmpty)
    }
}
