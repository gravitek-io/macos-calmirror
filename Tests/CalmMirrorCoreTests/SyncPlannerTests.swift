import XCTest
@testable import CalmMirrorCore

/// Characterizes reconciliation without EventKit access or calendar writes.
final class SyncPlannerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let rule = MirrorRule(title: "Work", sourceCalendarIdentifier: "source",
                                  targetCalendarIdentifier: "target", windowDays: 30,
                                  blockerLabel: "Busy", usePlaceholder: true)

    private func event(_ id: String = "meeting", title: String = "Review", offset: TimeInterval = 0,
                       duration: TimeInterval = 3600, notes: String? = nil) -> SourceEventSnapshot {
        SourceEventSnapshot(identifier: id, title: title, startDate: start.addingTimeInterval(offset),
                            endDate: start.addingTimeInterval(offset + duration), isAllDay: false, notes: notes)
    }

    private func record(_ event: SourceEventSnapshot, hash: String? = nil, rule: MirrorRule? = nil) -> SyncRecord {
        let rule = rule ?? self.rule
        let hash = hash ?? ContentHasher.computeContentHash(
            startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
            blockerTitle: rule.blockerTitle(forSourceTitle: event.title),
            origins: BlockerNotes.originsForBlocker(sourceNotes: event.notes,
                                                   sourceCalendarIdentifier: rule.sourceCalendarIdentifier)
        )
        return SyncRecord(sourceEventIdentifier: event.identifier, sourceExternalIdentifier: "external",
                          sourceStartDate: event.startDate, sourceEndDate: event.endDate,
                          sourceIsAllDay: event.isAllDay, sourceContentHash: hash,
                          blockerEventIdentifier: "blocker-\(event.identifier)", blockerExternalIdentifier: "remote",
                          lastSyncedAt: start)
    }

    func testClassifiesNewChangedUnchangedAndRemovedOccurrencesInOrder() {
        let original = event("unchanged")
        let changed = event("changed", offset: 7200)
        let deleted = record(event("deleted", offset: 14400))
        let plan = SyncPlanner.plan(sourceEvents: [event("new", offset: 21600), changed, original],
                                    existingRecords: [record(original), deleted, record(changed, hash: "old")], rule: rule)
        XCTAssertEqual(plan.newEvents.map(\.sourceIndex), [0])
        XCTAssertEqual(plan.changedEvents.map { $0.source.sourceIndex }, [1])
        XCTAssertEqual(plan.unchangedRecords.map(\.id), [record(original).id])
        XCTAssertEqual(plan.orphanedRecords.map(\.id), [deleted.id])
    }

    func testRescheduleRetainsExistingDeleteAndCreateSemantics() {
        let previous = record(event())
        let plan = SyncPlanner.plan(sourceEvents: [event(offset: 3600)], existingRecords: [previous], rule: rule)
        XCTAssertEqual(plan.newEvents.count, 1)
        XCTAssertEqual(plan.orphanedRecords.map(\.id), [previous.id])
        XCTAssertTrue(plan.changedEvents.isEmpty)
    }

    func testRecurringOccurrencesWithSharedIdentifierStayDistinct() {
        let events = [event(offset: 0), event(offset: 86400), event(offset: 172800)]
        let records = events.map { record($0) }
        let plan = SyncPlanner.plan(sourceEvents: events, existingRecords: records, rule: rule)
        XCTAssertEqual(plan.unchangedRecords.map(\.id), records.map(\.id))
        XCTAssertTrue(plan.newEvents.isEmpty)
        XCTAssertTrue(plan.orphanedRecords.isEmpty)
    }

    func testDuplicatePrefersAlreadyMirroredOccurrenceAndRemovesRedundantRecord() {
        let first = event("first")
        let second = event("second")
        let preferred = record(second)
        var plan = SyncPlanner.plan(sourceEvents: [first, second], existingRecords: [preferred], rule: rule)
        XCTAssertTrue(plan.newEvents.isEmpty)
        XCTAssertEqual(plan.unchangedRecords.map(\.id), [preferred.id])
        let redundant = record(first)
        plan = SyncPlanner.plan(sourceEvents: [first, second], existingRecords: [redundant, preferred], rule: rule)
        XCTAssertEqual(plan.unchangedRecords.map(\.id), [redundant.id])
        XCTAssertEqual(plan.orphanedRecords.map(\.id), [preferred.id])
    }

    func testRenameOnlyChangesBlockerWhenTitlesAreMirrored() {
        let renamed = event(title: "New title")
        var plan = SyncPlanner.plan(sourceEvents: [renamed], existingRecords: [record(event())], rule: rule)
        XCTAssertEqual(plan.unchangedRecords.count, 1)
        var titleRule = rule
        titleRule.usePlaceholder = false
        plan = SyncPlanner.plan(sourceEvents: [renamed], existingRecords: [record(event(), rule: titleRule)], rule: titleRule)
        XCTAssertEqual(plan.changedEvents.count, 1)
    }

    func testDurationAndOriginChangesUpdateExistingBlocker() {
        let previous = record(event())
        for changed in [event(duration: 7200), event(notes: BlockerNotes.compose(origins: ["other"]))] {
            let plan = SyncPlanner.plan(sourceEvents: [changed], existingRecords: [previous], rule: rule)
            XCTAssertEqual(plan.changedEvents.map { $0.existingRecord.id }, [previous.id])
            XCTAssertTrue(plan.orphanedRecords.isEmpty)
            XCTAssertTrue(plan.newEvents.isEmpty)
        }
    }

    func testAllDayFlagKeepsOtherwiseIdenticalOccurrencesDistinct() {
        let timed = event("timed")
        let allDay = SourceEventSnapshot(identifier: "all-day", title: timed.title,
                                         startDate: timed.startDate, endDate: timed.endDate,
                                         isAllDay: true, notes: nil)
        let plan = SyncPlanner.plan(sourceEvents: [timed, allDay], existingRecords: [], rule: rule)
        XCTAssertEqual(plan.newEvents.map(\.sourceIndex), [0, 1])
        XCTAssertNotEqual(plan.newEvents[0].contentHash, plan.newEvents[1].contentHash)
    }

    func testDuplicateRecordIDsKeepLastRecordForComparison() {
        let source = event()
        let good = record(source)
        let stale = record(source, hash: "stale")
        let plan = SyncPlanner.plan(sourceEvents: [source], existingRecords: [good, stale], rule: rule)
        XCTAssertEqual(plan.changedEvents.first?.existingRecord.sourceContentHash, "stale")
        XCTAssertTrue(plan.unchangedRecords.isEmpty)
    }
}
