import Foundation

/// Manages persistence of sync execution logs in a single rolling JSON file.
///
/// All sync executions across all rules are logged to a single file at
/// `~/Library/Application Support/CalMirror/logs/sync-logs.json`.
/// Entries older than 30 days are pruned at the start of each write operation.
///
/// File writes use `Data.write(to:options:.atomic)` to prevent corruption
/// from interrupted writes (e.g., process killed mid-write, system sleep).
/// Only one sync process runs at a time, so no file locking is needed.
public final class SyncLogStore {

    /// Number of days to retain log entries.
    public static let retentionDays: Int = 30

    private let logFileURL: URL

    /// Shared JSON encoder configured for sync log serialization.
    /// Uses ISO 8601 date format and pretty-printed output for readability.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    /// Shared JSON decoder configured for sync log deserialization.
    /// Uses ISO 8601 date format to match the encoder.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Initializes the store with the default application support directory.
    ///
    /// Creates the `~/Library/Application Support/CalMirror/logs/` directory
    /// if it does not already exist.
    ///
    /// - Throws: If the logs directory cannot be created.
    public init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let logsDir = appSupport
            .appendingPathComponent("CalMirror", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        self.logFileURL = logsDir.appendingPathComponent("sync-logs.json")
    }

    /// For testing: inject a custom log file URL.
    ///
    /// Creates the parent directory if it does not exist, ensuring the file
    /// can be written during tests without manual directory setup.
    ///
    /// - Parameter logFileURL: The URL to use for the log file.
    /// - Throws: If the parent directory cannot be created.
    internal init(logFileURL: URL) throws {
        self.logFileURL = logFileURL
        let parentDir = logFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Read Operations

    /// Reads and decodes all sync logs from the log file.
    ///
    /// Returns an empty array if the file does not exist or if decoding fails
    /// (e.g., the file was corrupted or contains an incompatible format).
    ///
    /// - Returns: All persisted sync log entries, ordered as stored on disk.
    public func loadLogs() -> [SyncLog] {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: logFileURL)
            return try decoder.decode([SyncLog].self, from: data)
        } catch {
            return []
        }
    }

    /// Returns only sync logs belonging to a specific mirror rule.
    ///
    /// Loads the full log file and filters entries by `ruleId`.
    /// Returns an empty array if the file does not exist.
    ///
    /// - Parameter ruleId: The UUID of the mirror rule to filter by.
    /// - Returns: Sync log entries matching the given rule, ordered as stored.
    public func loadLogs(for ruleId: UUID) -> [SyncLog] {
        loadLogs().filter { $0.ruleId == ruleId }
    }

    /// Returns the most recent sync log entries, up to the requested count.
    ///
    /// Logs are assumed to be stored in chronological order (oldest first).
    /// This method returns the last `count` entries from the file.
    ///
    /// - Parameter count: The maximum number of recent entries to return.
    /// - Returns: Up to `count` entries from the end of the log, preserving order.
    public func loadLogs(last count: Int) -> [SyncLog] {
        let allLogs = loadLogs()
        return Array(allLogs.suffix(count))
    }

    /// Returns the sync logs recorded at or after the given date.
    ///
    /// Used by the app to collect the results of a sync it triggered: it
    /// remembers the trigger time and reads back whatever the agent appended
    /// afterwards. A log's `timestamp` is the moment its rule sync started,
    /// so a run launched after `date` always qualifies.
    ///
    /// Timestamps are persisted in ISO 8601 with second precision, so the
    /// bound is truncated to the second before comparing. Otherwise a run
    /// that started in the same second as the trigger would be missed.
    ///
    /// - Parameter date: The inclusive lower bound on `timestamp`.
    /// - Returns: Matching entries, ordered as stored on disk.
    public func loadLogs(since date: Date) -> [SyncLog] {
        let bound = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        return loadLogs().filter { $0.timestamp >= bound }
    }

    /// Returns the most recent sync log for every rule that has one.
    ///
    /// Drives the per-rule status shown in the app ("Last synced 2 min ago").
    /// Entries are compared by `timestamp` rather than by file position so
    /// the result stays correct even if the file is not chronological.
    ///
    /// - Returns: A dictionary keyed by rule identifier.
    public func latestLogByRule() -> [UUID: SyncLog] {
        var latest: [UUID: SyncLog] = [:]
        for log in loadLogs() {
            if let current = latest[log.ruleId], current.timestamp >= log.timestamp {
                continue
            }
            latest[log.ruleId] = log
        }
        return latest
    }

    // MARK: - Write Operations

    /// Appends a new sync log entry to the log file.
    ///
    /// This method:
    /// 1. Loads existing log entries from disk.
    /// 2. Appends the new entry.
    /// 3. Prunes entries older than ``retentionDays``.
    /// 4. Writes the result atomically to prevent file corruption.
    ///
    /// - Parameter log: The sync log entry to append.
    /// - Throws: If the file cannot be encoded or written.
    public func appendLog(_ log: SyncLog) throws {
        var logs = loadLogs()
        logs.append(log)
        let pruned = Self.pruneEntries(logs)
        try writeLogs(pruned)
    }

    /// Removes log entries older than the retention window and writes back.
    ///
    /// Entries whose `timestamp` is earlier than `now - retentionDays` are
    /// discarded. The pruned list is written atomically to disk.
    ///
    /// - Throws: If the file cannot be encoded or written.
    public func pruneOldEntries() throws {
        let logs = loadLogs()
        let pruned = Self.pruneEntries(logs)
        try writeLogs(pruned)
    }

    // MARK: - Private Helpers

    /// Filters out log entries older than the retention period.
    ///
    /// Uses ``retentionDays`` to compute the cutoff date from the current time.
    /// Entries with a `timestamp` before the cutoff are discarded.
    ///
    /// - Parameter logs: The full list of log entries to filter.
    /// - Returns: Only the entries within the retention window.
    private static func pruneEntries(_ logs: [SyncLog]) -> [SyncLog] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        ) ?? Date()
        return logs.filter { $0.timestamp >= cutoff }
    }

    /// Encodes and writes the log array to disk atomically.
    ///
    /// Uses `.atomic` write option to ensure the file is never left in a
    /// partially written state if the process is interrupted.
    ///
    /// - Parameter logs: The complete list of log entries to persist.
    /// - Throws: If encoding or writing fails.
    private func writeLogs(_ logs: [SyncLog]) throws {
        let data = try encoder.encode(logs)
        try data.write(to: logFileURL, options: .atomic)
    }
}
