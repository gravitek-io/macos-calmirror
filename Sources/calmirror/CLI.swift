// CLI.swift
// CalmMirror -- CLI entry point
//
// Defines the root command and subcommands for the `calmirror` executable.
// This target is built as a standalone CLI tool invoked by launchd or
// interactively from the terminal.

import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation

/// Typealias to avoid name collision between the `AgentStatus` model from
/// CalmMirrorCore and the `AgentStatus` ParsableCommand subcommand.
private typealias LaunchdAgentStatus = AgentStatus

// MARK: - Helpers

/// Writes a message to standard error, followed by a newline.
///
/// All error, warning, and diagnostic output is directed to stderr so that
/// structured stdout output remains clean for piping and JSON consumers.
///
/// - Parameter message: The text to write to stderr.
private func writeToStderr(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(Data((message + "\n").utf8))
}

/// Short identifier for human-readable output (first 8 characters of a UUID or calendar id).
///
/// - Parameter identifier: The full identifier string.
/// - Returns: The first 8 characters, or the full string if shorter.
private func shortID(_ identifier: String) -> String {
    String(identifier.prefix(8))
}

/// Ensures the app has full calendar access, requesting it if needed.
///
/// When the authorization status is `.notDetermined`, this function
/// triggers the system permission prompt using a semaphore to bridge
/// the async `requestFullAccessToEvents()` API into synchronous context.
/// If access is denied or the request fails, prints an error to stderr
/// and terminates with exit code 4.
private func requireCalendarAccess() {
    let status = CalendarService.shared.checkAuthorizationStatus()

    switch status {
    case .fullAccess:
        return

    case .notDetermined:
        // Bridge the async permission request into synchronous CLI context.
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false

        Task {
            do {
                granted = try await CalendarService.shared.requestAccess()
            } catch {
                // Request failed; granted stays false.
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard granted else {
            writeToStderr(
                "error: calendar access denied. "
                + "Grant Full Access in System Settings > Privacy & Security > Calendars."
            )
            Darwin.exit(4)
        }

    default:
        writeToStderr(
            "error: calendar access denied. "
            + "Grant Full Access in System Settings > Privacy & Security > Calendars."
        )
        Darwin.exit(4)
    }
}

// MARK: - Signal Handling

/// Flag indicating that a graceful termination has been requested.
///
/// Set to `true` by the SIGTERM and SIGINT signal handlers installed
/// in the Sync command. The sync loop checks this flag between rules
/// and stops processing additional rules when set, allowing the
/// currently executing rule to finish its commit batch before exiting.
///
/// This ensures launchd stop/restart does not leave orphaned or
/// incomplete sync state. Completed rules retain their full state;
/// only un-started rules are skipped.
private var shouldTerminate = false

// MARK: - Root Command

/// Root command for the CalmMirror CLI.
///
/// `CalmMirror` acts as the top-level entry point that dispatches to
/// subcommands. Run `calmirror --help` for usage information.
@main
struct CalmMirror: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "calmirror",
        abstract: "Calendar event mirroring tool for macOS",
        subcommands: [
            Version.self,
            Calendars.self,
            Rules.self,
            Sync.self,
            Logs.self,
            Status.self,
            Agent.self
        ]
    )
}

// MARK: - Version Subcommand

extension CalmMirror {

    /// Prints the current version of the CalmMirror CLI.
    ///
    /// Usage:
    /// ```
    /// calmirror version
    /// ```
    struct Version: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Print the current version"
        )

        func run() throws {
            print("calmirror 1.3.0")
        }
    }
}

// MARK: - Calendars Subcommand

extension CalmMirror {

    /// Lists all calendars available in Apple Calendar, grouped by account.
    ///
    /// This subcommand helps users discover calendar identifiers needed
    /// for `rules add`. Calendars are grouped by their source account
    /// (iCloud, Google, Exchange, etc.) and annotated with writability.
    ///
    /// Usage:
    /// ```
    /// calmirror calendars          # human-readable table
    /// calmirror calendars --json   # JSON output
    /// ```
    ///
    /// Exit code 4 if calendar access is denied.
    struct Calendars: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "List all calendars grouped by account"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            requireCalendarAccess()

            let accounts = CalendarService.shared.calendarsByAccount()

            if accounts.isEmpty || accounts.allSatisfy({ $0.calendars.isEmpty }) {
                if json {
                    print("[]")
                } else {
                    print("No calendars found in Apple Calendar.")
                }
                return
            }

            if json {
                printCalendarsJSON(accounts)
            } else {
                printCalendarsHuman(accounts)
            }
        }

        /// Prints calendars in a human-readable format grouped by account.
        ///
        /// Each account is printed as a header, followed by indented lines
        /// showing calendar ID (first 8 chars), title, and writability.
        private func printCalendarsHuman(
            _ accounts: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])]
        ) {
            for (index, group) in accounts.enumerated() {
                if index > 0 { print() }
                print(group.account)
                for entry in group.calendars {
                    let idShort = shortID(entry.calendar.calendarIdentifier)
                    let title = entry.calendar.title
                    let access = entry.writable ? "read/write" : "read-only"
                    print("  \(idShort)  \(title)  \(access)")
                }
            }
        }

        /// Prints calendars as a JSON array of account objects.
        ///
        /// Each account includes its name, type, and nested calendars with
        /// full identifiers, titles, hex colors, and writability flags.
        private func printCalendarsJSON(
            _ accounts: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])]
        ) {
            var result: [[String: Any]] = []

            for group in accounts {
                var accountDict: [String: Any] = [
                    "accountName": group.account
                ]

                var calendarsArray: [[String: Any]] = []
                for entry in group.calendars {
                    let cal = entry.calendar
                    var calDict: [String: Any] = [
                        "id": cal.calendarIdentifier,
                        "title": cal.title,
                        "writable": entry.writable
                    ]

                    // Include CGColor as hex if available.
                    if let cgColor = cal.cgColor,
                       let components = cgColor.components,
                       cgColor.numberOfComponents >= 3 {
                        let r = Int(components[0] * 255)
                        let g = Int(components[1] * 255)
                        let b = Int(components[2] * 255)
                        calDict["color"] = String(format: "#%02X%02X%02X", r, g, b)
                    }

                    calendarsArray.append(calDict)
                }
                accountDict["calendars"] = calendarsArray
                result.append(accountDict)
            }

            // Serialize with sorted keys for deterministic output.
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

// MARK: - Rules Subcommand Group

extension CalmMirror {

    /// Parent command for rule management subcommands.
    ///
    /// Rules define how events from a source calendar are mirrored as
    /// blocker entries in a target calendar. This command group provides
    /// CRUD operations for rules stored in UserDefaults.
    ///
    /// Usage:
    /// ```
    /// calmirror rules list
    /// calmirror rules add --title <name> --source <id> --target <id> --window <days> --label <text>
    /// calmirror rules remove <uuid>
    /// calmirror rules enable <uuid>
    /// calmirror rules disable <uuid>
    /// ```
    struct Rules: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Manage sync rules",
            subcommands: [
                List.self,
                Add.self,
                Remove.self,
                Enable.self,
                Disable.self
            ],
            defaultSubcommand: List.self
        )
    }
}

// MARK: - Rules List

extension CalmMirror.Rules {

    /// Lists all configured sync rules.
    ///
    /// Displays rules in a tabular format by default, or as a JSON array
    /// when `--json` is passed. Includes short IDs, labels, source/target
    /// calendar references, window size, and enabled/disabled status.
    ///
    /// Exit code 0 on success (even if no rules exist).
    struct List: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "List all sync rules"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            let store = RuleStore()
            let rules = store.loadRules()

            if rules.isEmpty {
                if json {
                    print("[]")
                } else {
                    print("No rules configured. Use 'calmirror rules add' to create one.")
                }
                return
            }

            if json {
                printRulesJSON(rules)
            } else {
                printRulesHuman(rules)
            }
        }

        /// Prints rules as a human-readable table with aligned columns.
        ///
        /// Columns: ID (8-char), TITLE, SOURCE (8-char), TARGET (8-char),
        /// WINDOW, MODE, STATUS. MODE is "fixed" when the rule uses a static
        /// placeholder label, or "source" when blockers mirror the event name.
        private func printRulesHuman(_ rules: [MirrorRule]) {
            // Right-pads a column to a fixed width using native Swift string
            // handling. Avoids C-string `%s` formatting, which crashes when a
            // Swift String is passed where a `char *` is expected.
            func column(_ value: String, width: Int) -> String {
                value.count >= width
                    ? value
                    : value + String(repeating: " ", count: width - value.count)
            }

            func formatRow(_ cells: [(String, Int)]) -> String {
                cells.map { column($0.0, width: $0.1) }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
            }

            // Header
            print(formatRow([
                ("ID", 10), ("TITLE", 24), ("SOURCE", 10),
                ("TARGET", 10), ("WINDOW", 8), ("MODE", 8), ("STATUS", 0)
            ]))

            for rule in rules {
                print(formatRow([
                    (shortID(rule.id.uuidString), 10),
                    (truncateLabel(rule.title, maxLength: 24), 24),
                    (shortID(rule.sourceCalendarIdentifier), 10),
                    (shortID(rule.targetCalendarIdentifier), 10),
                    ("\(rule.windowDays)d", 8),
                    (rule.usePlaceholder ? "fixed" : "source", 8),
                    (rule.isEnabled ? "enabled" : "disabled", 0)
                ]))
            }
        }

        /// Truncates a label string for human-readable table display.
        ///
        /// - Parameters:
        ///   - label: The original label text.
        ///   - maxLength: Maximum character width allowed.
        /// - Returns: The label truncated with "..." if it exceeds maxLength.
        private func truncateLabel(_ label: String, maxLength: Int) -> String {
            if label.count <= maxLength {
                return label
            }
            return String(label.prefix(maxLength - 3)) + "..."
        }

        /// Prints the full rule array as JSON with all fields.
        private func printRulesJSON(_ rules: [MirrorRule]) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            if let data = try? encoder.encode(rules),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            } else {
                print("[]")
            }
        }
    }
}

// MARK: - Rules Add

extension CalmMirror.Rules {

    /// Adds a new sync rule after validating all parameters.
    ///
    /// Validates that:
    /// - Source and target calendars exist in EventKit
    /// - Source and target are different calendars
    /// - Target calendar is writable
    /// - Window is within the valid range (1-120 days)
    /// - Label is not empty
    ///
    /// On success, prints a confirmation with the new rule's full UUID.
    ///
    /// Exit codes:
    /// - 0: Rule created successfully
    /// - 3: Validation error
    /// - 4: Calendar access denied
    struct Add: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Add a new sync rule"
        )

        @Option(name: .long, help: "Human-readable name for this rule")
        var title: String

        @Option(name: .long, help: "Calendar identifier for the source")
        var source: String

        @Option(name: .long, help: "Calendar identifier for the target")
        var target: String

        @Option(name: .long, help: "Number of days in the sliding time window (1-120)")
        var window: Int

        @Flag(name: .long, help: "Use a fixed placeholder label instead of mirroring the source event name")
        var usePlaceholder: Bool = false

        @Option(name: .long, help: "Fixed label for blocker events (required with --use-placeholder; ignored otherwise)")
        var label: String = ""

        func run() throws {
            requireCalendarAccess()

            // Validate title is not empty.
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                writeToStderr("error: title must not be empty.")
                Darwin.exit(3)
            }

            // Validate source calendar exists.
            guard let sourceCal = CalendarService.shared.calendar(withIdentifier: source) else {
                writeToStderr("error: source calendar '\(source)' not found.")
                Darwin.exit(3)
            }

            // Validate target calendar exists.
            guard let targetCal = CalendarService.shared.calendar(withIdentifier: target) else {
                writeToStderr("error: target calendar '\(target)' not found.")
                Darwin.exit(3)
            }

            // Validate source != target.
            if source == target {
                writeToStderr("error: source and target calendars must be different.")
                Darwin.exit(3)
            }

            // Validate target is writable.
            if !targetCal.allowsContentModifications {
                writeToStderr("error: target calendar '\(targetCal.title)' is read-only.")
                Darwin.exit(3)
            }

            // Validate window range (model enforces 1...120).
            if !(1...120).contains(window) {
                writeToStderr("error: window must be between 1 and 120 days.")
                Darwin.exit(3)
            }

            // Validate label is not empty when the placeholder is in use.
            if usePlaceholder && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                writeToStderr("error: --label must not be empty when --use-placeholder is set.")
                Darwin.exit(3)
            }

            // Create and persist the rule.
            let rule = MirrorRule(
                title: title,
                sourceCalendarIdentifier: source,
                targetCalendarIdentifier: target,
                windowDays: window,
                blockerLabel: label,
                usePlaceholder: usePlaceholder
            )

            let store = RuleStore()
            do {
                try store.addRule(rule)
            } catch {
                writeToStderr("error: failed to save rule: \(error.localizedDescription)")
                Darwin.exit(2)
            }

            // Print confirmation.
            let sourceAccount = sourceCal.source?.title ?? "Unknown"
            let targetAccount = targetCal.source?.title ?? "Unknown"

            print("Rule created: \(rule.id.uuidString)")
            print("  Title:  \(title)")
            print("  Source: \(sourceCal.title) (\(sourceAccount))")
            print("  Target: \(targetCal.title) (\(targetAccount))")
            print("  Window: \(window) days")
            if usePlaceholder {
                print("  Title mode: fixed placeholder")
                print("  Label:  \(label)")
            } else {
                print("  Title mode: mirror source event name, e.g. \"[\(title)] <event name>\"")
            }
        }
    }
}

// MARK: - Rules Remove

extension CalmMirror.Rules {

    /// Removes an existing rule by its UUID with cascade cleanup.
    ///
    /// Deletes all managed blocker events from the target calendar,
    /// removes the sync record file, and then removes the rule
    /// configuration from UserDefaults.
    ///
    /// Exit codes:
    /// - 0: Rule removed successfully
    /// - 3: Rule UUID not found
    struct Remove: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Remove a sync rule by UUID"
        )

        @Argument(help: "UUID of the rule to remove")
        var uuid: String

        func run() throws {
            guard let ruleID = UUID(uuidString: uuid) else {
                writeToStderr("error: '\(uuid)' is not a valid UUID.")
                Darwin.exit(3)
            }

            let store = RuleStore()
            do {
                let syncRecordStore = try SyncRecordStore()
                let result = try store.removeRuleWithCleanup(
                    id: ruleID,
                    syncRecordStore: syncRecordStore,
                    calendarService: CalendarService.shared
                )
                print("Rule removed: \(result.rule.id.uuidString) (\"\(result.rule.title)\")")
                if result.blockersRemoved > 0 {
                    print("Cleaned up \(result.blockersRemoved) blocker event\(result.blockersRemoved == 1 ? "" : "s") from target calendar.")
                }
            } catch is RuleStoreError {
                writeToStderr("error: rule '\(uuid)' not found.")
                Darwin.exit(3)
            } catch {
                writeToStderr("error: failed to remove rule: \(error.localizedDescription)")
                Darwin.exit(2)
            }
        }
    }
}

// MARK: - Rules Enable

extension CalmMirror.Rules {

    /// Enables a previously disabled rule so it will be included in sync cycles.
    ///
    /// If the rule is already enabled, this is a no-op that still exits 0.
    ///
    /// Exit codes:
    /// - 0: Rule enabled (or was already enabled)
    /// - 3: Rule UUID not found
    struct Enable: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Enable a sync rule by UUID"
        )

        @Argument(help: "UUID of the rule to enable")
        var uuid: String

        func run() throws {
            guard let ruleID = UUID(uuidString: uuid) else {
                writeToStderr("error: '\(uuid)' is not a valid UUID.")
                Darwin.exit(3)
            }

            let store = RuleStore()
            do {
                try store.enableRule(id: ruleID)
                let rule = store.rule(for: ruleID)
                let label = rule?.title ?? "unknown"
                print("Rule enabled: \(shortID(ruleID.uuidString)) (\"\(label)\")")
            } catch is RuleStoreError {
                writeToStderr("error: rule '\(uuid)' not found.")
                Darwin.exit(3)
            } catch {
                writeToStderr("error: failed to enable rule: \(error.localizedDescription)")
                Darwin.exit(2)
            }
        }
    }
}

// MARK: - Rules Disable

extension CalmMirror.Rules {

    /// Disables a rule so it is skipped during sync cycles.
    ///
    /// Existing blocker events are preserved. Use `rules remove` to also
    /// clean up blockers from the target calendar.
    ///
    /// Exit codes:
    /// - 0: Rule disabled (or was already disabled)
    /// - 3: Rule UUID not found
    struct Disable: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Disable a sync rule by UUID"
        )

        @Argument(help: "UUID of the rule to disable")
        var uuid: String

        func run() throws {
            guard let ruleID = UUID(uuidString: uuid) else {
                writeToStderr("error: '\(uuid)' is not a valid UUID.")
                Darwin.exit(3)
            }

            let store = RuleStore()
            do {
                try store.disableRule(id: ruleID)
                let rule = store.rule(for: ruleID)
                let label = rule?.title ?? "unknown"
                print("Rule disabled: \(shortID(ruleID.uuidString)) (\"\(label)\")")
                print("Existing blockers are preserved. Use 'calmirror rules remove' to also clean up blockers.")
            } catch is RuleStoreError {
                writeToStderr("error: rule '\(uuid)' not found.")
                Darwin.exit(3)
            } catch {
                writeToStderr("error: failed to disable rule: \(error.localizedDescription)")
                Darwin.exit(2)
            }
        }
    }
}

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

// MARK: - Agent Subcommand Group

extension CalmMirror {

    /// Parent command for launchd agent management subcommands.
    ///
    /// The agent runs `calmirror sync` every 15 minutes in the background
    /// via a macOS launchd user agent. This command group provides install,
    /// uninstall, and status operations for the agent plist.
    ///
    /// Usage:
    /// ```
    /// calmirror agent                # show agent status (default)
    /// calmirror agent install        # install and start the agent
    /// calmirror agent uninstall      # stop and remove the agent
    /// calmirror agent status         # show agent status
    /// calmirror agent status --json  # show agent status as JSON
    /// ```
    struct Agent: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Manage the background sync agent",
            subcommands: [
                AgentInstall.self,
                AgentUninstall.self,
                AgentStatus.self
            ],
            defaultSubcommand: AgentStatus.self
        )
    }
}

// MARK: - Agent Install

extension CalmMirror.Agent {

    /// Installs the launchd agent plist and loads it into the current user session.
    ///
    /// The agent is configured to run `calmirror sync` every 15 minutes as
    /// a background process. It starts automatically at login and persists
    /// when the GUI application is closed.
    ///
    /// If the agent is already installed, prints a message and exits with
    /// code 0 (no-op).
    ///
    /// Exit codes:
    /// - 0: Agent installed successfully, or already installed
    /// - 1: Plist written but launchctl bootstrap failed
    /// - 2: Plist write failed
    struct AgentInstall: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install and start the background sync agent"
        )

        func run() throws {
            let launchdManager = LaunchdManager()

            // If already installed, inform the user and exit cleanly.
            if launchdManager.isInstalled() {
                print(
                    "Agent is already installed and running. "
                    + "Use 'calmirror agent uninstall' first to reinstall."
                )
                return
            }

            // Resolve the CLI binary path from the current process.
            let cliPath = (CommandLine.arguments[0] as NSString).resolvingSymlinksInPath

            do {
                try launchdManager.install(cliPath: cliPath)
            } catch let error as LaunchdManagerError {
                switch error {
                case .plistWriteFailed(let detail):
                    writeToStderr("error: \(detail)")
                    Darwin.exit(2)
                case .launchctlFailed(let detail):
                    writeToStderr(
                        "error: plist written but launchctl bootstrap failed: \(detail). "
                        + "Try manually: launchctl bootstrap gui/\(getuid()) \(launchdManager.plistURL().path)"
                    )
                    Darwin.exit(1)
                case .alreadyInstalled:
                    // Should not reach here due to the guard above,
                    // but handle gracefully.
                    print(
                        "Agent is already installed and running. "
                        + "Use 'calmirror agent uninstall' first to reinstall."
                    )
                    return
                case .notInstalled:
                    // Should not occur during install.
                    writeToStderr("error: unexpected state during install.")
                    Darwin.exit(2)
                }
            }

            // Print confirmation with details.
            let plistPath = launchdManager.plistURL().path
            let intervalMinutes = LaunchdManager.syncInterval / 60

            print("Agent installed and loaded.")
            print("  Plist:    \(plistPath)")
            print("  Interval: every \(intervalMinutes) minutes")
            print("  Status:   running")
        }
    }
}

// MARK: - Agent Uninstall

extension CalmMirror.Agent {

    /// Unloads the launchd agent and removes its plist file.
    ///
    /// If the agent is not installed, prints an error to stderr and exits
    /// with code 2.
    ///
    /// Exit codes:
    /// - 0: Agent unloaded and plist removed
    /// - 1: Partial uninstall (bootout failed but plist removed, or vice versa)
    /// - 2: Agent was not installed
    struct AgentUninstall: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Stop and remove the background sync agent"
        )

        func run() throws {
            let launchdManager = LaunchdManager()

            // Verify the agent is installed before attempting uninstall.
            guard launchdManager.isInstalled() else {
                writeToStderr("error: agent is not installed. Nothing to uninstall.")
                Darwin.exit(2)
            }

            do {
                try launchdManager.uninstall()
            } catch let error as LaunchdManagerError {
                switch error {
                case .launchctlFailed(let detail):
                    // Bootout failed but plist may have been removed.
                    writeToStderr("warning: launchctl bootout failed: \(detail). Plist removed anyway.")
                    Darwin.exit(1)
                case .plistWriteFailed(let detail):
                    // Plist removal failed.
                    writeToStderr("error: \(detail)")
                    Darwin.exit(1)
                case .notInstalled:
                    writeToStderr("error: agent is not installed. Nothing to uninstall.")
                    Darwin.exit(2)
                case .alreadyInstalled:
                    writeToStderr("error: unexpected state during uninstall.")
                    Darwin.exit(1)
                }
            }

            print("Agent unloaded and removed.")
        }
    }
}

// MARK: - Agent Status

extension CalmMirror.Agent {

    /// Displays the current status of the launchd sync agent.
    ///
    /// Shows whether the agent is installed, running, its PID, plist
    /// location, and the configured sync interval. Supports both
    /// human-readable and JSON output.
    ///
    /// Exit codes:
    /// - 0: Always (status is informational)
    struct AgentStatus: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the background sync agent status"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            let launchdManager = LaunchdManager()
            let agentStatus = launchdManager.status()

            if json {
                printAgentStatusJSON(agentStatus)
            } else {
                printAgentStatusHuman(agentStatus)
            }
        }

        /// Prints agent status in a human-readable format.
        ///
        /// Example output:
        /// ```
        /// Agent Status
        ///   Installed: yes
        ///   Running:   yes (PID 12345)
        ///   Plist:     ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist
        ///   Interval:  900s (15 minutes)
        /// ```
        private func printAgentStatusHuman(_ status: LaunchdAgentStatus) {
            let installedText = status.installed ? "yes" : "no"
            let runningText: String
            if status.running, let pid = status.pid {
                runningText = "yes (PID \(pid))"
            } else if status.running {
                runningText = "yes"
            } else {
                runningText = "no"
            }

            let intervalMinutes = status.intervalSeconds / 60

            print("Agent Status")
            print("  Installed: \(installedText)")
            print("  Running:   \(runningText)")
            print("  Plist:     \(status.plistPath)")
            print("  Interval:  \(status.intervalSeconds)s (\(intervalMinutes) minutes)")
        }

        /// Prints agent status as a JSON object.
        ///
        /// Includes installation state, running state, PID, plist path,
        /// and the configured interval in seconds.
        private func printAgentStatusJSON(_ status: LaunchdAgentStatus) {
            var result: [String: Any] = [
                "installed": status.installed,
                "running": status.running,
                "plistPath": status.plistPath,
                "intervalSeconds": status.intervalSeconds
            ]

            if let pid = status.pid {
                result["pid"] = pid
            } else {
                result["pid"] = NSNull()
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
    }
}
