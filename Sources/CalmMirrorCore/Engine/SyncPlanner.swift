import Foundation

/// Immutable source data needed to decide which blockers change. No EventKit
/// access is required, so planning can be tested without calendar permissions.
struct SourceEventSnapshot {
    let identifier: String
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
}

/// A source occurrence and the desired fingerprint of its blocker.
struct PlannedSourceEvent {
    let sourceIndex: Int
    let recordID: String
    let contentHash: String
    let blockerKey: BlockerKey
}

/// The changes required before adoption and calendar writes take place.
struct SyncPlan {
    struct Update {
        let source: PlannedSourceEvent
        let existingRecord: SyncRecord
    }

    let newEvents: [PlannedSourceEvent]
    let changedEvents: [Update]
    let orphanedRecords: [SyncRecord]
    let unchangedRecords: [SyncRecord]
}

/// Pure reconciliation of source occurrences with the last persisted mappings.
/// Input order, duplicate preference and second-precision occurrence identities
/// match the sync engine's original algorithm.
enum SyncPlanner {
    static func plan(
        sourceEvents: [SourceEventSnapshot],
        existingRecords: [SyncRecord],
        rule: MirrorRule
    ) -> SyncPlan {
        // Preserve last-record-wins behavior if stored IDs are duplicated.
        var recordLookup: [String: SyncRecord] = [:]
        for record in existingRecords {
            recordLookup[record.id] = record
        }

        let candidates = sourceEvents.enumerated().map { index, event in
            let title = rule.blockerTitle(forSourceTitle: event.title)
            return PlannedSourceEvent(
                sourceIndex: index,
                recordID: SyncRecord.occurrenceID(identifier: event.identifier, startDate: event.startDate),
                contentHash: ContentHasher.computeContentHash(
                    startDate: event.startDate, endDate: event.endDate,
                    isAllDay: event.isAllDay, blockerTitle: title,
                    origins: BlockerNotes.originsForBlocker(
                        sourceNotes: event.notes,
                        sourceCalendarIdentifier: rule.sourceCalendarIdentifier
                    )
                ),
                blockerKey: BlockerKey(title: title, startDate: event.startDate,
                                       endDate: event.endDate, isAllDay: event.isAllDay)
            )
        }
        let uniqueCandidates = BlockerDeduplicator.collapseDuplicates(
            candidates, blockerKey: { $0.blockerKey },
            isAlreadyMirrored: { recordLookup[$0.recordID] != nil }
        )

        var newEvents: [PlannedSourceEvent] = []
        var changedEvents: [SyncPlan.Update] = []
        var matchedRecordIDs: Set<String> = []
        for source in uniqueCandidates {
            guard let record = recordLookup[source.recordID] else {
                newEvents.append(source)
                continue
            }
            matchedRecordIDs.insert(source.recordID)
            if record.sourceContentHash != source.contentHash {
                changedEvents.append(SyncPlan.Update(source: source, existingRecord: record))
            }
        }

        let changedRecordIDs = Set(changedEvents.map { $0.existingRecord.id })
        return SyncPlan(
            newEvents: newEvents,
            changedEvents: changedEvents,
            orphanedRecords: existingRecords.filter { !matchedRecordIDs.contains($0.id) },
            unchangedRecords: existingRecords.filter {
                matchedRecordIDs.contains($0.id) && !changedRecordIDs.contains($0.id)
            }
        )
    }
}
