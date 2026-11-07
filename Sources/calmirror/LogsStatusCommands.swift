import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

// MARK: - Logs Subcommand

extension CalmMirror {

    /// Displays sync execution logs from the persistent log store.
    ///
    /// Logs are shown in reverse chronological order (most recent first).
    /// Optionally filter by a specific rule UUID and limit the number of
    /// entries displayed.
    ///
    /// Usage:
    /// ```
    /// calmirror logs                        # last 10 log entries
    /// calmirror logs --last 50              # last 50 log entries
    /// calmirror logs --rule <uuid>          # logs for a specific rule
    /// calmirror logs --json                 # JSON output
    /// ```
    ///
    /// Exit codes:
    /// - 0: Success
    /// - 2: Read failure (could not load logs)
    /// - 3: Invalid UUID or rule not found
    struct Logs: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Show sync execution logs"
        )

        @Option(name: .long, help: "Show logs only for the rule with this UUID")
        var rule: String?

        @Option(name: .long, help: "Number of recent entries to show (1-1000, default 10)")
        var last: Int = 10

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            // Validate --last range.
            if !(1...1000).contains(last) {
                writeToStderr("error: --last must be between 1 and 1000.")
                Darwin.exit(3)
            }

            // Load the log store.
            let logStore: SyncLogStore
            do {
                logStore = try SyncLogStore()
            } catch {
                writeToStderr("error: failed to open log store: \(error.localizedDescription)")
                Darwin.exit(2)
            }

            // Load all logs.
            var logs = logStore.loadLogs()

            // If --rule is provided, validate and filter.
            if let ruleUUIDString = rule {
                guard let ruleUUID = UUID(uuidString: ruleUUIDString) else {
                    writeToStderr("error: '\(ruleUUIDString)' is not a valid UUID.")
                    Darwin.exit(3)
                }

                // Verify the rule exists in the rule store.
                let ruleStore = RuleStore()
                guard ruleStore.rule(for: ruleUUID) != nil else {
                    writeToStderr("error: rule '\(ruleUUIDString)' not found.")
                    Darwin.exit(3)
                }

                logs = logs.filter { $0.ruleId == ruleUUID }
            }

            // Apply --last limit (take the most recent entries).
            logs = Array(logs.suffix(last))

            // Handle empty result.
            if logs.isEmpty {
                if json {
                    print("[]")
                } else {
                    print("No sync logs found.")
                }
                return
            }

            // Print results in the requested format.
            if json {
                printLogsJSON(logs)
            } else {
                printLogsHuman(logs)
            }
        }

        // MARK: - Human-Readable Output

        /// Prints log entries in a human-readable table format.
        ///
        /// Each line shows the timestamp, result (OK/ERROR), rule label with
        /// short ID, and a summary of changes or the first error message.
        /// Logs are displayed in reverse chronological order (most recent first).
        ///
        /// Format:
        /// ```
        /// 2026-01-30 14:15:00  OK     Rule "Work -> Personal" (a1b2c3d4): +3 -1 ~0
        /// 2026-01-30 14:00:00  ERROR  Rule "Work -> Personal" (a1b2c3d4): target calendar not found
        /// ```
        private func printLogsHuman(_ logs: [SyncLog]) {
            let ruleStore = RuleStore()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            // Display most recent first.
            for log in logs.reversed() {
                let timestamp = dateFormatter.string(from: log.timestamp)
                let result = log.isSuccess ? "OK    " : "ERROR "
                let ruleLabel = ruleStore.rule(for: log.ruleId)?.title
                    ?? shortID(log.ruleId.uuidString)
                let ruleShortID = shortID(log.ruleId.uuidString)

                if log.isSuccess {
                    print(
                        "\(timestamp)  \(result) Rule \"\(ruleLabel)\" (\(ruleShortID)): "
                        + "+\(log.addedCount) -\(log.removedCount) ~\(log.updatedCount)"
                    )
                } else {
                    // Show the first error message for failed syncs.
                    let errorMessage = log.errors.first?.message ?? "unknown error"
                    print(
                        "\(timestamp)  \(result) Rule \"\(ruleLabel)\" (\(ruleShortID)): "
                        + "\(errorMessage)"
                    )
                }
            }
        }

        // MARK: - JSON Output

        /// Prints log entries as a JSON array.
        ///
        /// Each object includes the timestamp, rule ID, result status,
        /// change counts, error details, and duration in milliseconds.
        private func printLogsJSON(_ logs: [SyncLog]) {
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var result: [[String: Any]] = []

            for log in logs.reversed() {
                var entry: [String: Any] = [
                    "timestamp": iso8601Formatter.string(from: log.timestamp),
                    "ruleId": log.ruleId.uuidString,
                    "result": log.isSuccess ? "ok" : "error",
                    "added": log.addedCount,
                    "removed": log.removedCount,
                    "updated": log.updatedCount,
                    "durationMs": Int(log.durationSeconds * 1000)
                ]

                if !log.errors.isEmpty {
                    entry["errors"] = log.errors.map { syncError -> [String: String] in
                        [
                            "code": syncError.code.rawValue,
                            "message": syncError.message
                        ]
                    }
                }

                result.append(entry)
            }

            if let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("[]")
            }
        }
    }
}

// MARK: - Status Subcommand

extension CalmMirror {

    /// Displays a summary of the current CalmMirror system status.
    ///
    /// Shows whether the launchd agent is installed, when the last sync
    /// ran, and how many rules are configured (with enabled/disabled breakdown).
    ///
    /// Usage:
    /// ```
    /// calmirror status          # human-readable summary
    /// calmirror status --json   # JSON output
    /// ```
    ///
    /// Exit codes:
    /// - 0: Always (unless read failure = 2)
    struct Status: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Show CalmMirror system status"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        /// Path to the launchd agent plist file.
        private static let agentPlistPath: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/Library/LaunchAgents/com.gravitek.calmirror.sync.plist"
        }()

        func run() throws {
            // 1. Check if launchd agent plist exists.
            let agentInstalled = FileManager.default.fileExists(atPath: Self.agentPlistPath)

            // 2. Load rules and compute counts.
            let ruleStore = RuleStore()
            let rules = ruleStore.loadRules()
            let totalRules = rules.count
            let enabledRules = rules.filter(\.isEnabled).count
            let disabledRules = totalRules - enabledRules

            // 3. Load the most recent sync log entry.
            let logStore: SyncLogStore
            do {
                logStore = try SyncLogStore()
            } catch {
                writeToStderr("error: failed to open log store: \(error.localizedDescription)")
                Darwin.exit(2)
            }

            let lastLog = logStore.loadLogs().last

            // 4. Output results.
            if json {
                printStatusJSON(
                    agentInstalled: agentInstalled,
                    totalRules: totalRules,
                    enabledRules: enabledRules,
                    disabledRules: disabledRules,
                    lastLog: lastLog
                )
            } else {
                printStatusHuman(
                    agentInstalled: agentInstalled,
                    totalRules: totalRules,
                    enabledRules: enabledRules,
                    disabledRules: disabledRules,
                    lastLog: lastLog
                )
            }
        }

        // MARK: - Human-Readable Output

        /// Prints a human-readable status summary.
        ///
        /// Shows the agent installation state, last sync timestamp with relative
        /// time, rule counts with enabled/disabled breakdown, and the last sync
        /// result if available.
        ///
        /// Example output:
        /// ```
        /// CalMirror Status
        ///   Agent:       installed
        ///   Last sync:   2026-01-30 14:15:00 (15 minutes ago)
        ///   Rules:       3 configured (2 enabled, 1 disabled)
        ///   Last result: OK (3 added, 1 removed)
        /// ```
        private func printStatusHuman(
            agentInstalled: Bool,
            totalRules: Int,
            enabledRules: Int,
            disabledRules: Int,
            lastLog: SyncLog?
        ) {
            let agentStatus = agentInstalled ? "installed" : "not installed"

            // Format last sync timestamp with relative time.
            let lastSyncText: String
            if let log = lastLog {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let absolute = dateFormatter.string(from: log.timestamp)
                let relative = relativeTimeString(from: log.timestamp)
                lastSyncText = "\(absolute) (\(relative))"
            } else {
                lastSyncText = "never"
            }

            // Format rules summary.
            let rulesText: String
            if totalRules == 0 {
                rulesText = "0 configured"
            } else {
                rulesText = "\(totalRules) configured (\(enabledRules) enabled, \(disabledRules) disabled)"
            }

            print("CalMirror Status")
            print("  Agent:       \(agentStatus)")
            print("  Last sync:   \(lastSyncText)")
            print("  Rules:       \(rulesText)")

            // Show last result if a log entry exists.
            if let log = lastLog {
                if log.isSuccess {
                    print(
                        "  Last result: OK (\(log.addedCount) added, \(log.removedCount) removed)"
                    )
                } else {
                    let errorMessage = log.errors.first?.message ?? "unknown error"
                    print("  Last result: ERROR (\(errorMessage))")
                }
            }

            // Hint to install agent if not present.
            if !agentInstalled {
                print("  Run 'calmirror agent install' to set up the background agent.")
            }
        }

        // MARK: - JSON Output

        /// Prints status information as a JSON object.
        ///
        /// Includes agent installation status, last sync details, and rule counts.
        private func printStatusJSON(
            agentInstalled: Bool,
            totalRules: Int,
            enabledRules: Int,
            disabledRules: Int,
            lastLog: SyncLog?
        ) {
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var result: [String: Any] = [
                "agent": [
                    "installed": agentInstalled
                ],
                "rules": [
                    "total": totalRules,
                    "enabled": enabledRules,
                    "disabled": disabledRules
                ]
            ]

            if let log = lastLog {
                var lastSyncDict: [String: Any] = [
                    "timestamp": iso8601Formatter.string(from: log.timestamp),
                    "ruleId": log.ruleId.uuidString,
                    "success": log.isSuccess,
                    "added": log.addedCount,
                    "removed": log.removedCount,
                    "updated": log.updatedCount
                ]

                if !log.errors.isEmpty {
                    lastSyncDict["errors"] = log.errors.map { syncError -> [String: String] in
                        [
                            "code": syncError.code.rawValue,
                            "message": syncError.message
                        ]
                    }
                }

                result["lastSync"] = lastSyncDict
            } else {
                result["lastSync"] = NSNull()
            }

            if let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                print("{}")
            }
        }

        // MARK: - Relative Time Helper

        /// Computes a human-readable relative time string from a past date.
        ///
        /// Produces strings like "15 minutes ago", "2 hours ago", "3 days ago".
        /// Handles seconds, minutes, hours, and days as the primary intervals.
        ///
        /// - Parameter date: The past date to compute the relative offset from.
        /// - Returns: A human-readable string describing how long ago the date was.
        private func relativeTimeString(from date: Date) -> String {
            let interval = Int(Date().timeIntervalSince(date))

            if interval < 60 {
                return interval == 1 ? "1 second ago" : "\(interval) seconds ago"
            }

            let minutes = interval / 60
            if minutes < 60 {
                return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
            }

            let hours = minutes / 60
            if hours < 24 {
                return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
            }

            let days = hours / 24
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}
