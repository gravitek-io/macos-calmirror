import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

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
