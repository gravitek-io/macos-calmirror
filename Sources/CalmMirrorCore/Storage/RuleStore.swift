import EventKit
import Foundation

/// Errors that can occur during rule store operations.
public enum RuleStoreError: Error, LocalizedError {
    /// The requested rule was not found in the store.
    case ruleNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .ruleNotFound(let id):
            return "No rule found with id \(id.uuidString)."
        }
    }
}

/// Manages persistence of mirror rules in UserDefaults shared suite.
///
/// Both the SwiftUI app and CLI tool access rules through this store
/// using the shared suite `com.gravitek.calmirror`, enabling configuration
/// changes in one to be immediately visible to the other.
public final class RuleStore: @unchecked Sendable {

    /// The shared suite name used by both the app and CLI.
    public static let suiteName = "com.gravitek.calmirror"

    private let defaults: UserDefaults

    public init() {
        // Use shared suite; fall back to standard if suite creation fails
        self.defaults = UserDefaults(suiteName: RuleStore.suiteName) ?? .standard
    }

    /// For testing: inject a custom UserDefaults instance.
    internal init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Read Operations

    /// Loads all persisted mirror rules from UserDefaults.
    ///
    /// Decodes the JSON data stored under `MirrorRule.userDefaultsKey`.
    /// Returns an empty array if no data is stored or if decoding fails.
    ///
    /// - Returns: The array of persisted mirror rules, or an empty array.
    public func loadRules() -> [MirrorRule] {
        guard let data = defaults.data(forKey: MirrorRule.userDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MirrorRule].self, from: data)
        } catch {
            return []
        }
    }

    /// Finds and returns a single rule by its identifier.
    ///
    /// - Parameter id: The UUID of the rule to look up.
    /// - Returns: The matching rule, or `nil` if no rule exists with that id.
    public func rule(for id: UUID) -> MirrorRule? {
        loadRules().first { $0.id == id }
    }

    // MARK: - Write Operations

    /// Encodes and persists the given array of rules to UserDefaults.
    ///
    /// Replaces the entire stored rule list with the provided array.
    /// Uses JSON encoding via `Codable` for cross-process compatibility.
    ///
    /// - Parameter rules: The complete array of rules to persist.
    public func saveRules(_ rules: [MirrorRule]) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }
        defaults.set(data, forKey: MirrorRule.userDefaultsKey)
    }

    /// Validates and appends a new rule to the persisted collection.
    ///
    /// Runs validation on the rule's configuration before saving.
    /// If validation fails, the rule is not added and the error is thrown.
    ///
    /// - Parameter rule: The new rule to add.
    /// - Throws: `MirrorRule.ValidationError` if the rule's configuration is invalid.
    public func addRule(_ rule: MirrorRule) throws {
        if let validationError = MirrorRule.validate(
            sourceCalendarIdentifier: rule.sourceCalendarIdentifier,
            targetCalendarIdentifier: rule.targetCalendarIdentifier,
            windowDays: rule.windowDays,
            blockerLabel: rule.blockerLabel
        ) {
            throw validationError
        }

        var rules = loadRules()
        rules.append(rule)
        saveRules(rules)
    }

    /// Replaces an existing rule with an updated version, matched by id.
    ///
    /// Locates the rule in the stored collection by its `id` property and
    /// replaces it with the provided updated rule.
    ///
    /// - Parameter rule: The updated rule (must have the same id as an existing rule).
    /// - Throws: `RuleStoreError.ruleNotFound` if no rule with the given id exists.
    public func updateRule(_ rule: MirrorRule) throws {
        var rules = loadRules()
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            throw RuleStoreError.ruleNotFound(rule.id)
        }
        rules[index] = rule
        saveRules(rules)
    }

    /// Removes a rule by its identifier and returns the removed rule.
    ///
    /// - Parameter id: The UUID of the rule to remove.
    /// - Returns: The rule that was removed from the store.
    /// - Throws: `RuleStoreError.ruleNotFound` if no rule with the given id exists.
    @discardableResult
    public func removeRule(id: UUID) throws -> MirrorRule {
        var rules = loadRules()
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw RuleStoreError.ruleNotFound(id)
        }
        let removed = rules.remove(at: index)
        saveRules(rules)
        return removed
    }

    /// Removes a rule and performs full cascade cleanup of associated data.
    ///
    /// This method ensures no orphaned data remains after a rule is deleted:
    /// 1. Loads the rule's sync records to identify managed blocker events.
    /// 2. Deletes each blocker event from the target calendar (primary identifier
    ///    lookup with external identifier fallback).
    /// 3. Commits all EventKit deletions in a single batch.
    /// 4. Deletes the sync record JSON file for the rule.
    /// 5. Removes the rule from UserDefaults.
    ///
    /// If a blocker event is no longer found in EventKit (e.g., the user already
    /// deleted it manually), it is silently skipped. The sync record file and
    /// rule entry are always cleaned up regardless of individual blocker deletion
    /// outcomes.
    ///
    /// - Parameters:
    ///   - id: The UUID of the rule to remove.
    ///   - syncRecordStore: The store managing per-rule sync record files.
    ///   - calendarService: The calendar service used for EventKit operations.
    /// - Returns: A tuple containing the removed rule and the count of blocker events
    ///   successfully deleted from the target calendar.
    /// - Throws: `RuleStoreError.ruleNotFound` if no rule with the given id exists.
    ///   EventKit or file system errors from cleanup operations are also propagated.
    @discardableResult
    public func removeRuleWithCleanup(
        id: UUID,
        syncRecordStore: SyncRecordStore,
        calendarService: CalendarService
    ) throws -> (rule: MirrorRule, blockersRemoved: Int) {

        // Verify the rule exists before performing cleanup.
        guard let _ = loadRules().first(where: { $0.id == id }) else {
            throw RuleStoreError.ruleNotFound(id)
        }

        // Step 1: Load sync records for this rule.
        let records = syncRecordStore.loadRecords(for: id)

        // Step 2: Delete each managed blocker event from EventKit.
        var blockersRemoved = 0
        for record in records {
            if let blockerEvent = findBlockerEvent(
                for: record,
                calendarService: calendarService
            ) {
                do {
                    try calendarService.deleteEvent(blockerEvent, commit: false)
                    blockersRemoved += 1
                } catch {
                    // Individual blocker deletion failure is non-fatal.
                    // The blocker may have been manually deleted or the calendar removed.
                }
            }
        }

        // Step 3: Commit all pending EventKit deletions in one batch.
        if blockersRemoved > 0 {
            try calendarService.commitChanges()
        }

        // Step 4: Delete the sync record JSON file.
        try syncRecordStore.deleteRecords(for: id)

        // Step 5: Remove the rule from UserDefaults.
        let removedRule = try removeRule(id: id)

        return (rule: removedRule, blockersRemoved: blockersRemoved)
    }

    // MARK: - Private Helpers

    /// Looks up a blocker event using the sync record's stored identifiers.
    ///
    /// Attempts the primary device-local `eventIdentifier` first. If not found
    /// (e.g., after Exchange re-sync), falls back to the cross-device
    /// `calendarItemExternalIdentifier`.
    ///
    /// - Parameters:
    ///   - record: The sync record containing the blocker's identifiers.
    ///   - calendarService: The calendar service used for EventKit lookups.
    /// - Returns: The matching `EKEvent`, or `nil` if the blocker no longer exists.
    private func findBlockerEvent(
        for record: SyncRecord,
        calendarService: CalendarService
    ) -> EKEvent? {
        // Primary lookup: device-local identifier (fast, single-item fetch).
        if let event = calendarService.findEvent(byIdentifier: record.blockerEventIdentifier) {
            return event
        }

        // Fallback: cross-device external identifier (may return multiple items).
        let items = calendarService.findEvents(byExternalIdentifier: record.blockerExternalIdentifier)
        return items.first { $0 is EKEvent } as? EKEvent
    }

    // MARK: - Toggle Operations

    /// Enables a rule by setting `isEnabled` to `true` and updating the timestamp.
    ///
    /// - Parameter id: The UUID of the rule to enable.
    /// - Throws: `RuleStoreError.ruleNotFound` if no rule with the given id exists.
    public func enableRule(id: UUID) throws {
        var rules = loadRules()
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw RuleStoreError.ruleNotFound(id)
        }
        rules[index].isEnabled = true
        rules[index].updatedAt = Date()
        saveRules(rules)
    }

    /// Disables a rule by setting `isEnabled` to `false` and updating the timestamp.
    ///
    /// - Parameter id: The UUID of the rule to disable.
    /// - Throws: `RuleStoreError.ruleNotFound` if no rule with the given id exists.
    public func disableRule(id: UUID) throws {
        var rules = loadRules()
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw RuleStoreError.ruleNotFound(id)
        }
        rules[index].isEnabled = false
        rules[index].updatedAt = Date()
        saveRules(rules)
    }
}
