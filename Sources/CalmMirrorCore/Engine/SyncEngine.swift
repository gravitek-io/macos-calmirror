import EventKit
import Foundation

/// Orchestrates calendar event synchronization for mirror rules.
///
/// The sync engine executes the core algorithm: fetch source events,
/// diff against existing sync records, create/update/delete blocker events,
/// and persist the updated state. Each rule is processed independently.
///
/// ## Algorithm Overview
/// 1. Validate source and target calendars exist and are writable.
/// 2. Fetch source events within the configured time window.
/// 3. Diff fetched events against persisted `SyncRecord` mappings.
/// 4. Execute create/update/delete operations for blocker events.
/// 5. Persist updated sync records and append a `SyncLog` entry.
///
/// ## Recurring Events
/// `predicateForEvents` automatically expands recurring events into
/// individual occurrences. Each occurrence is treated as a standalone
/// event, producing one blocker per occurrence within the sync window.
public final class SyncEngine {

    // MARK: - Constants

    /// Maximum number of EventKit save/remove operations before an
    /// intermediate commit. Keeps memory pressure low and limits the
    /// blast radius of a single failed commit.
    private static let batchSize = 50

    // MARK: - Dependencies

    private let calendarService: CalendarService
    private let syncRecordStore: SyncRecordStore
    private let syncLogStore: SyncLogStore

    // MARK: - Initialization

    /// Creates a sync engine with the specified dependencies.
    ///
    /// - Parameters:
    ///   - calendarService: The calendar service used for EventKit operations.
    ///     Defaults to the shared singleton.
    ///   - syncRecordStore: The store used to persist source-to-blocker mappings.
    ///   - syncLogStore: The store used to persist sync execution logs.
    public init(
        calendarService: CalendarService = .shared,
        syncRecordStore: SyncRecordStore,
        syncLogStore: SyncLogStore
    ) {
        self.calendarService = calendarService
        self.syncRecordStore = syncRecordStore
        self.syncLogStore = syncLogStore
    }

    // MARK: - Public API

    /// Executes the sync algorithm for a single mirror rule.
    ///
    /// Fetches source events within the rule's time window, diffs them
    /// against existing sync records, and creates/updates/deletes blocker
    /// events in the target calendar accordingly. Results are persisted
    /// and a `SyncLog` entry is returned.
    ///
    /// - Parameters:
    ///   - rule: The mirror rule defining source/target calendars and settings.
    ///   - dryRun: When `true`, the diff is computed but no EventKit changes
    ///     are written and no records are saved. Useful for previewing changes.
    /// - Returns: A `SyncLog` describing the outcome of this sync execution.
    public func sync(rule: MirrorRule, dryRun: Bool = false) -> SyncLog {
        let startTime = Date()

        // ------------------------------------------------------------------
        // Step 1: Validate calendars
        // ------------------------------------------------------------------

        guard let sourceCalendar = calendarService.calendar(withIdentifier: rule.sourceCalendarIdentifier) else {
            return buildErrorLog(
                rule: rule,
                startTime: startTime,
                error: SyncError(
                    code: .calendarNotFound,
                    message: "Source calendar not found (identifier: \(rule.sourceCalendarIdentifier))."
                )
            )
        }

        guard let targetCalendar = calendarService.calendar(withIdentifier: rule.targetCalendarIdentifier) else {
            return buildErrorLog(
                rule: rule,
                startTime: startTime,
                error: SyncError(
                    code: .calendarNotFound,
                    message: "Target calendar not found (identifier: \(rule.targetCalendarIdentifier))."
                )
            )
        }

        guard targetCalendar.allowsContentModifications else {
            return buildErrorLog(
                rule: rule,
                startTime: startTime,
                error: SyncError(
                    code: .calendarReadOnly,
                    message: "Target calendar \"\(targetCalendar.title)\" is read-only."
                )
            )
        }

        // ------------------------------------------------------------------
        // Step 2: Compute time window
        // ------------------------------------------------------------------

        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .day, value: rule.windowDays, to: windowStart)!

        // ------------------------------------------------------------------
        // Step 3: Fetch source events and filter cancelled ones
        // ------------------------------------------------------------------

        let allSourceEvents = calendarService.fetchEvents(
            in: sourceCalendar,
            from: windowStart,
            to: windowEnd
        )

        let sourceEvents = allSourceEvents.filter { $0.status != .canceled }

        // ------------------------------------------------------------------
        // Step 4: Load existing sync records
        // ------------------------------------------------------------------

        let existingRecords = syncRecordStore.loadRecords(for: rule.id)

        // ------------------------------------------------------------------
        // Step 5: Diff — classify each event and record
        // ------------------------------------------------------------------

        let diffResult = computeDiff(sourceEvents: sourceEvents, existingRecords: existingRecords)

        // ------------------------------------------------------------------
        // Step 6: Execute changes (unless dry run)
        // ------------------------------------------------------------------

        var errors: [SyncError] = []
        var createdRecords: [SyncRecord] = []
        var updatedRecords: [SyncRecord] = []
        var removedChanges: [BlockerChange] = []
        var addedChanges: [BlockerChange] = []
        var updatedChanges: [BlockerChange] = []
        let now = Date()

        if !dryRun {
            var operationCount = 0

            // --- Create blockers for NEW events ---
            for newItem in diffResult.newEvents {
                let event = newItem.event
                do {
                    let blocker = try calendarService.createBlockerEvent(
                        in: targetCalendar,
                        title: rule.blockerLabel,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        commit: false
                    )

                    let record = SyncRecord(
                        sourceEventIdentifier: event.eventIdentifier,
                        sourceExternalIdentifier: event.calendarItemExternalIdentifier,
                        sourceStartDate: event.startDate,
                        sourceEndDate: event.endDate,
                        sourceIsAllDay: event.isAllDay,
                        sourceContentHash: newItem.contentHash,
                        blockerEventIdentifier: blocker.eventIdentifier,
                        blockerExternalIdentifier: blocker.calendarItemExternalIdentifier,
                        lastSyncedAt: now
                    )

                    createdRecords.append(record)
                    addedChanges.append(BlockerChange(
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay
                    ))

                    operationCount += 1
                    if operationCount % Self.batchSize == 0 {
                        try calendarService.commitChanges()
                    }
                } catch {
                    errors.append(SyncError(
                        code: .blockerOperationFailed,
                        message: "Failed to create blocker for source event \(event.eventIdentifier ?? "unknown"): \(error.localizedDescription)"
                    ))
                }
            }

            // --- Update blockers for CHANGED events ---
            for changedItem in diffResult.changedEvents {
                let event = changedItem.event
                let existingRecord = changedItem.existingRecord

                do {
                    // Look up the blocker event: primary identifier first, then external fallback.
                    guard let blockerEvent = findBlockerEvent(for: existingRecord) else {
                        errors.append(SyncError(
                            code: .blockerOperationFailed,
                            message: "Blocker event not found for update (source: \(event.eventIdentifier ?? "unknown"))."
                        ))
                        continue
                    }

                    try calendarService.updateBlockerEvent(
                        blockerEvent,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        commit: false
                    )

                    let record = SyncRecord(
                        sourceEventIdentifier: event.eventIdentifier,
                        sourceExternalIdentifier: event.calendarItemExternalIdentifier,
                        sourceStartDate: event.startDate,
                        sourceEndDate: event.endDate,
                        sourceIsAllDay: event.isAllDay,
                        sourceContentHash: changedItem.contentHash,
                        blockerEventIdentifier: blockerEvent.eventIdentifier,
                        blockerExternalIdentifier: blockerEvent.calendarItemExternalIdentifier,
                        lastSyncedAt: now
                    )

                    updatedRecords.append(record)
                    updatedChanges.append(BlockerChange(
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay
                    ))

                    operationCount += 1
                    if operationCount % Self.batchSize == 0 {
                        try calendarService.commitChanges()
                    }
                } catch {
                    errors.append(SyncError(
                        code: .blockerOperationFailed,
                        message: "Failed to update blocker for source event \(event.eventIdentifier ?? "unknown"): \(error.localizedDescription)"
                    ))
                }
            }

            // --- Delete blockers for ORPHANED records ---
            for orphanedRecord in diffResult.orphanedRecords {
                do {
                    if let blockerEvent = findBlockerEvent(for: orphanedRecord) {
                        try calendarService.deleteEvent(blockerEvent, commit: false)

                        operationCount += 1
                        if operationCount % Self.batchSize == 0 {
                            try calendarService.commitChanges()
                        }
                    }

                    removedChanges.append(BlockerChange(
                        startDate: orphanedRecord.sourceStartDate,
                        endDate: orphanedRecord.sourceEndDate,
                        isAllDay: orphanedRecord.sourceIsAllDay
                    ))
                } catch {
                    errors.append(SyncError(
                        code: .blockerOperationFailed,
                        message: "Failed to delete orphaned blocker \(orphanedRecord.blockerEventIdentifier): \(error.localizedDescription)"
                    ))
                }
            }

            // --- Final commit for any remaining uncommitted operations ---
            if operationCount % Self.batchSize != 0 {
                do {
                    try calendarService.commitChanges()
                } catch {
                    errors.append(SyncError(
                        code: .eventKitInternal,
                        message: "Final commit failed: \(error.localizedDescription)"
                    ))
                }
            }
        } else {
            // Dry run: populate change arrays for reporting without executing.
            for newItem in diffResult.newEvents {
                addedChanges.append(BlockerChange(
                    startDate: newItem.event.startDate,
                    endDate: newItem.event.endDate,
                    isAllDay: newItem.event.isAllDay
                ))
            }
            for changedItem in diffResult.changedEvents {
                updatedChanges.append(BlockerChange(
                    startDate: changedItem.event.startDate,
                    endDate: changedItem.event.endDate,
                    isAllDay: changedItem.event.isAllDay
                ))
            }
            for orphanedRecord in diffResult.orphanedRecords {
                removedChanges.append(BlockerChange(
                    startDate: orphanedRecord.sourceStartDate,
                    endDate: orphanedRecord.sourceEndDate,
                    isAllDay: orphanedRecord.sourceIsAllDay
                ))
            }
        }

        // ------------------------------------------------------------------
        // Step 7: Build updated records list and persist
        // ------------------------------------------------------------------

        // Combine: new records + updated records + unchanged records.
        // Orphaned records are excluded since their blockers were deleted.
        var finalRecords: [SyncRecord] = []
        finalRecords.append(contentsOf: createdRecords)
        finalRecords.append(contentsOf: updatedRecords)
        finalRecords.append(contentsOf: diffResult.unchangedRecords)

        if !dryRun {
            do {
                try syncRecordStore.saveRecords(finalRecords, for: rule.id)
            } catch {
                errors.append(SyncError(
                    code: .unknown,
                    message: "Failed to save sync records: \(error.localizedDescription)"
                ))
            }
        }

        // ------------------------------------------------------------------
        // Step 8: Build and persist the sync log
        // ------------------------------------------------------------------

        let duration = Date().timeIntervalSince(startTime)

        let syncLog = SyncLog(
            ruleId: rule.id,
            timestamp: startTime,
            durationSeconds: duration,
            added: addedChanges,
            removed: removedChanges,
            updated: updatedChanges,
            errors: errors
        )

        if !dryRun {
            do {
                try syncLogStore.appendLog(syncLog)
            } catch {
                // Log persistence failure is non-fatal; the sync itself succeeded.
                // The error is already captured in the returned SyncLog via the errors array
                // if we wanted, but since the log object is already built, we silently
                // accept this failure. The next successful appendLog will prune old entries.
            }
        }

        return syncLog
    }

    /// Executes the sync algorithm for all enabled rules sequentially.
    ///
    /// Disabled rules are skipped. Each enabled rule is synced independently;
    /// a failure in one rule does not prevent subsequent rules from running.
    ///
    /// - Parameters:
    ///   - rules: The array of mirror rules to process.
    ///   - dryRun: When `true`, no EventKit changes are written.
    /// - Returns: An array of `SyncLog` entries, one per enabled rule processed.
    public func syncAll(rules: [MirrorRule], dryRun: Bool = false) -> [SyncLog] {
        rules
            .filter(\.isEnabled)
            .map { sync(rule: $0, dryRun: dryRun) }
    }

    // MARK: - Diff Algorithm

    /// Intermediate types used during the diff phase to classify source events.
    private struct NewEvent {
        let event: EKEvent
        let contentHash: String
    }

    private struct ChangedEvent {
        let event: EKEvent
        let contentHash: String
        let existingRecord: SyncRecord
    }

    /// Result of diffing source events against existing sync records.
    private struct DiffResult {
        /// Source events with no matching sync record — blockers must be created.
        let newEvents: [NewEvent]
        /// Source events whose content hash differs from the record — blockers must be updated.
        let changedEvents: [ChangedEvent]
        /// Existing records with no matching source event — blockers must be deleted.
        let orphanedRecords: [SyncRecord]
        /// Existing records whose content hash matches the source event — no action needed.
        let unchangedRecords: [SyncRecord]
    }

    /// Computes the diff between fetched source events and persisted sync records.
    ///
    /// Uses a composite key of `sourceEventIdentifier` and `sourceStartDate`
    /// (via `SyncRecord.id`) to match events to records. This correctly handles
    /// recurring event occurrences, which share the same `eventIdentifier` but
    /// have different start dates.
    ///
    /// - Parameters:
    ///   - sourceEvents: Events fetched from the source calendar within the time window.
    ///   - existingRecords: Previously persisted sync records for this rule.
    /// - Returns: A `DiffResult` classifying each event and record.
    private func computeDiff(
        sourceEvents: [EKEvent],
        existingRecords: [SyncRecord]
    ) -> DiffResult {
        // Build a lookup by the composite record ID to handle recurring occurrences.
        // Record.id = "{sourceEventIdentifier}_{sourceStartDate.timeIntervalSince1970}"
        var recordLookup: [String: SyncRecord] = [:]
        for record in existingRecords {
            recordLookup[record.id] = record
        }

        var newEvents: [NewEvent] = []
        var changedEvents: [ChangedEvent] = []
        var matchedRecordIds: Set<String> = []

        for event in sourceEvents {
            let contentHash = ContentHasher.computeContentHash(
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )

            // Build the same composite key that SyncRecord.id uses.
            let compositeKey = "\(event.eventIdentifier ?? "")_\(Int(event.startDate.timeIntervalSince1970))"

            if let existingRecord = recordLookup[compositeKey] {
                matchedRecordIds.insert(compositeKey)

                if existingRecord.sourceContentHash == contentHash {
                    // UNCHANGED — hash matches, no action needed.
                } else {
                    // CHANGED — hash differs, blocker must be updated.
                    changedEvents.append(ChangedEvent(
                        event: event,
                        contentHash: contentHash,
                        existingRecord: existingRecord
                    ))
                }
            } else {
                // NEW — no existing record, blocker must be created.
                newEvents.append(NewEvent(event: event, contentHash: contentHash))
            }
        }

        // Records not matched by any source event are orphaned.
        let orphanedRecords = existingRecords.filter { !matchedRecordIds.contains($0.id) }

        // Unchanged records are matched records that were not classified as changed.
        let changedRecordIds = Set(changedEvents.map { $0.existingRecord.id })
        let unchangedRecords = existingRecords.filter {
            matchedRecordIds.contains($0.id) && !changedRecordIds.contains($0.id)
        }

        return DiffResult(
            newEvents: newEvents,
            changedEvents: changedEvents,
            orphanedRecords: orphanedRecords,
            unchangedRecords: unchangedRecords
        )
    }

    // MARK: - Private Helpers

    /// Looks up a blocker event using the sync record's stored identifiers.
    ///
    /// Attempts the primary device-local `eventIdentifier` first. If not found
    /// (e.g., after Exchange re-sync), falls back to the cross-device
    /// `calendarItemExternalIdentifier`.
    ///
    /// - Parameter record: The sync record containing the blocker's identifiers.
    /// - Returns: The matching `EKEvent`, or `nil` if the blocker no longer exists.
    private func findBlockerEvent(for record: SyncRecord) -> EKEvent? {
        // Primary lookup: device-local identifier (fast, single-item fetch).
        if let event = calendarService.findEvent(byIdentifier: record.blockerEventIdentifier) {
            return event
        }

        // Fallback: cross-device external identifier (may return multiple items).
        let items = calendarService.findEvents(byExternalIdentifier: record.blockerExternalIdentifier)
        return items.first { $0 is EKEvent } as? EKEvent
    }

    /// Builds a `SyncLog` containing a single error for early-exit scenarios.
    ///
    /// Used when calendar validation fails and no sync operations can be performed.
    /// The log is persisted and returned so the UI can display the failure reason.
    ///
    /// - Parameters:
    ///   - rule: The mirror rule that failed validation.
    ///   - startTime: The timestamp when sync execution began.
    ///   - error: The validation error to include in the log.
    /// - Returns: A `SyncLog` with no changes and the provided error.
    private func buildErrorLog(rule: MirrorRule, startTime: Date, error: SyncError) -> SyncLog {
        let duration = Date().timeIntervalSince(startTime)

        let syncLog = SyncLog(
            ruleId: rule.id,
            timestamp: startTime,
            durationSeconds: duration,
            added: [],
            removed: [],
            updated: [],
            errors: [error]
        )

        do {
            try syncLogStore.appendLog(syncLog)
        } catch {
            // Log persistence failure is non-fatal for error logs.
        }

        return syncLog
    }
}
