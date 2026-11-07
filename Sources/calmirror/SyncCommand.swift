import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

// MARK: - Sync Subcommand

extension CalmMirror {

    /// Executes the sync algorithm for configured mirror rules.
    ///
    /// By default, all enabled rules are synced. Use `--rule` to sync a single
    /// rule by UUID. The `--dry-run` flag previews changes without writing to
    /// EventKit.
    ///
    /// Usage:
    /// ```
    /// calmirror sync                     # sync all enabled rules
    /// calmirror sync --rule <uuid>       # sync a single rule
    /// calmirror sync --dry-run           # preview changes only
    /// calmirror sync --json              # JSON output
    /// calmirror sync --quiet             # suppress stdout output
    /// ```
    ///
    /// Exit codes:
    /// - 0: All rules synced successfully
    /// - 1: Partial failure (some rules had errors)
    /// - 2: All rules failed
    /// - 3: No rules found or specified rule not found
    /// - 4: Calendar access denied
    struct Sync: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Run calendar sync for configured rules"
        )

        @Option(name: .long, help: "Sync only the rule with this UUID")
        var rule: String?

        @Flag(name: .long, help: "Preview changes without writing to EventKit")
        var dryRun = false

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        @Flag(name: .long, help: "Suppress all stdout output")
        var quiet = false

        func run() throws {
            requireCalendarAccess()

            // Install signal handlers for graceful termination.
            // When SIGTERM or SIGINT is received, the `shouldTerminate`
            // flag is set. The sync loop checks this flag between rules,
            // allowing the current rule to finish before exiting.
            installSignalHandlers()

            // Load rules from the rule store.
            let ruleStore = RuleStore()
            let allRules = ruleStore.loadRules()

            // If --rule is provided, filter to that single rule.
            let rulesToSync: [MirrorRule]

            if let ruleUUIDString = rule {
                guard let ruleUUID = UUID(uuidString: ruleUUIDString) else {
                    writeToStderr("error: '\(ruleUUIDString)' is not a valid UUID.")
                    Darwin.exit(3)
                }

                guard let matchedRule = allRules.first(where: { $0.id == ruleUUID }) else {
                    writeToStderr("error: rule '\(ruleUUIDString)' not found.")
                    Darwin.exit(3)
                }

                rulesToSync = [matchedRule]
            } else {
                rulesToSync = allRules
            }

            // Exit early if there are no rules to process.
            if rulesToSync.isEmpty {
                if json {
                    printSyncJSON(logs: [], dryRun: dryRun)
                } else if !quiet {
                    print("No rules configured. Use 'calmirror rules add' to create one.")
                }
                Darwin.exit(3)
            }

            // Create the sync engine with required stores.
            let syncRecordStore = try SyncRecordStore()
            let syncLogStore = try SyncLogStore()
            let syncEngine = SyncEngine(
                syncRecordStore: syncRecordStore,
                syncLogStore: syncLogStore
            )

            // Execute sync rule-by-rule, checking for termination between
            // rules. This allows a SIGTERM/SIGINT to stop processing
            // additional rules while letting the current one finish its
            // commit batch and write valid state.
            let enabledRules = rulesToSync.filter(\.isEnabled)
            var logs: [SyncLog] = []
            var interrupted = false

            for syncRule in enabledRules {
                // Check for termination signal before starting each rule.
                if shouldTerminate {
                    interrupted = true
                    writeToStderr(
                        "info: termination signal received. "
                        + "Stopping after \(logs.count) of \(enabledRules.count) rules."
                    )
                    break
                }

                let log = syncEngine.sync(rule: syncRule, dryRun: dryRun)
                logs.append(log)
            }

            // Output results (including partial results if interrupted).
            if json {
                printSyncJSON(logs: logs, dryRun: dryRun)
            } else if !quiet {
                printSyncHuman(logs: logs, rules: rulesToSync, dryRun: dryRun)
            }

            // If interrupted, always exit with code 1 (partial).
            if interrupted {
                Darwin.exit(1)
            }

            // Determine exit code based on sync outcomes.
            let exitCode = computeSyncExitCode(logs: logs)
            if exitCode != 0 {
                Darwin.exit(exitCode)
            }
        }

        // MARK: - Signal Handling Setup

        /// Installs SIGTERM and SIGINT handlers for graceful termination.
        ///
        /// Uses POSIX `signal()` to register lightweight handlers that set
        /// the `shouldTerminate` flag. The sync loop checks this flag
        /// between rules and stops processing when set, ensuring the
        /// current rule finishes its commit batch and writes valid state.
        ///
        /// This is critical for launchd integration: when launchd sends
        /// SIGTERM to stop the agent, the sync must not leave orphaned
        /// or incomplete sync records.
        private func installSignalHandlers() {
            signal(SIGTERM) { _ in
                shouldTerminate = true
            }
            signal(SIGINT) { _ in
                shouldTerminate = true
            }
        }

        // MARK: - Human-Readable Output

        /// Prints a human-readable summary of the sync results.
        ///
        /// For each rule, shows the counts of added, removed, and updated blocker
        /// events. In dry-run mode, prefixes the output and uses future-tense
        /// verbs ("to add" instead of "added").
        ///
        /// - Parameters:
        ///   - logs: The sync log entries produced by the engine.
        ///   - rules: The rules that were synced, used for label lookup.
        ///   - dryRun: Whether this was a dry-run execution.
        private func printSyncHuman(
            logs: [SyncLog],
            rules: [MirrorRule],
            dryRun: Bool
        ) {
            let prefix = dryRun ? "Dry run" : "Sync"
            let addedVerb = dryRun ? "to add" : "added"
            let removedVerb = dryRun ? "to remove" : "removed"
            let updatedVerb = dryRun ? "to update" : "updated"

            // Build a lookup from rule ID to rule for label display.
            let ruleLookup = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

            print("\(prefix) completed: \(logs.count) rule\(logs.count == 1 ? "" : "s") processed")

            var totalAdded = 0
            var totalRemoved = 0
            var totalUpdated = 0

            for log in logs {
                let label = ruleLookup[log.ruleId]?.title ?? "Unknown"
                let ruleShortID = shortID(log.ruleId.uuidString)

                print(
                    "  Rule \"\(label)\" (\(ruleShortID)): "
                    + "+\(log.addedCount) \(addedVerb), "
                    + "-\(log.removedCount) \(removedVerb), "
                    + "~\(log.updatedCount) \(updatedVerb)"
                )

                // Print any errors for this rule.
                for syncError in log.errors {
                    writeToStderr("  error [\(ruleShortID)]: \(syncError.message)")
                }

                totalAdded += log.addedCount
                totalRemoved += log.removedCount
                totalUpdated += log.updatedCount
            }

            print(
                "Total: \(totalAdded) \(addedVerb), "
                + "\(totalRemoved) \(removedVerb), "
                + "\(totalUpdated) \(updatedVerb)"
            )
        }

        // MARK: - JSON Output

        /// Prints a JSON representation of the sync results.
        ///
        /// Includes a timestamp, dry-run flag, per-rule details with change
        /// counts and errors, and aggregate totals.
        ///
        /// - Parameters:
        ///   - logs: The sync log entries produced by the engine.
        ///   - dryRun: Whether this was a dry-run execution.
        private func printSyncJSON(logs: [SyncLog], dryRun: Bool) {
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var rulesArray: [[String: Any]] = []

            var totalAdded = 0
            var totalRemoved = 0
            var totalUpdated = 0

            for log in logs {
                var ruleDict: [String: Any] = [
                    "ruleId": log.ruleId.uuidString,
                    "timestamp": iso8601Formatter.string(from: log.timestamp),
                    "durationSeconds": log.durationSeconds,
                    "added": log.addedCount,
                    "removed": log.removedCount,
                    "updated": log.updatedCount,
                    "success": log.isSuccess
                ]

                if !log.errors.isEmpty {
                    ruleDict["errors"] = log.errors.map { error -> [String: String] in
                        [
                            "code": error.code.rawValue,
                            "message": error.message
                        ]
                    }
                }

                rulesArray.append(ruleDict)

                totalAdded += log.addedCount
                totalRemoved += log.removedCount
                totalUpdated += log.updatedCount
            }

            let result: [String: Any] = [
                "timestamp": iso8601Formatter.string(from: Date()),
                "dryRun": dryRun,
                "rules": rulesArray,
                "totals": [
                    "added": totalAdded,
                    "removed": totalRemoved,
                    "updated": totalUpdated,
                    "rulesProcessed": logs.count
                ]
            ]

            if let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                print("{}")
            }
        }

        // MARK: - Exit Code

        /// Computes the appropriate exit code based on sync log outcomes.
        ///
        /// - Parameter logs: The sync log entries to evaluate.
        /// - Returns: 0 if all succeeded, 1 if partially failed, 2 if all failed.
        private func computeSyncExitCode(logs: [SyncLog]) -> Int32 {
            guard !logs.isEmpty else { return 3 }

            let successCount = logs.filter(\.isSuccess).count

            if successCount == logs.count {
                return 0
            } else if successCount == 0 {
                return 2
            } else {
                return 1
            }
        }
    }
}
