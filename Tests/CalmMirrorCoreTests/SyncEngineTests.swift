import XCTest
@testable import CalmMirrorCore

/// Unit tests for the SyncEngine's diff algorithm and model-layer integration (T035, T036).
///
/// The SyncEngine depends on `CalendarService` which wraps `EKEventStore` and
/// requires actual calendar access. These tests therefore focus on the logic
/// that **can** be validated without EventKit:
///
/// - **T035 (Diff algorithm):** SyncLog output structure, computed properties,
///   and ContentHasher integration used by the diff for change detection.
/// - **T036 (Blocker privacy):** BlockerChange data minimality, SyncRecord
///   composite-ID derivation, SyncError codes, and the blocker notes tag.
final class SyncEngineTests: XCTestCase {

    // MARK: - Fixed Fixtures

    /// Wednesday 2025-01-15 09:00:00 UTC
    private let fixtureStart = Date(timeIntervalSince1970: 1_736_931_600)
    /// Wednesday 2025-01-15 10:00:00 UTC (one hour later)
    private let fixtureEnd = Date(timeIntervalSince1970: 1_736_935_200)

    // MARK: - Helpers

    /// Creates a `BlockerChange` with sensible defaults.
    ///
    /// - Parameters:
    ///   - startDate: Start date of the blocker. Defaults to `fixtureStart`.
    ///   - endDate: End date of the blocker. Defaults to `fixtureEnd`.
    ///   - isAllDay: Whether the blocker is all-day. Defaults to `false`.
    /// - Returns: A fully initialised `BlockerChange`.
    private func makeBlockerChange(
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false
    ) -> BlockerChange {
        BlockerChange(
            startDate: startDate ?? fixtureStart,
            endDate: endDate ?? fixtureEnd,
            isAllDay: isAllDay
        )
    }

    /// Creates a `SyncLog` with customisable arrays for adds/removes/updates/errors.
    ///
    /// - Parameters:
    ///   - added: Blocker events created. Defaults to empty.
    ///   - removed: Blocker events deleted. Defaults to empty.
    ///   - updated: Blocker events modified. Defaults to empty.
    ///   - errors: Errors encountered. Defaults to empty.
    /// - Returns: A fully initialised `SyncLog`.
    private func makeSyncLog(
        added: [BlockerChange] = [],
        removed: [BlockerChange] = [],
        updated: [BlockerChange] = [],
        errors: [SyncError] = []
    ) -> SyncLog {
        SyncLog(
            ruleId: UUID(),
            timestamp: Date(),
            durationSeconds: 0.25,
            added: added,
            removed: removed,
            updated: updated,
            errors: errors
        )
    }

    /// Creates a `SyncRecord` with the given source event identifier and start date.
    ///
    /// All other fields are populated with deterministic placeholder values.
    ///
    /// - Parameters:
    ///   - sourceId: The source event identifier string.
    ///   - startDate: The source event start date.
    ///   - endDate: The source event end date. Defaults to one hour after `startDate`.
    ///   - isAllDay: Whether the source event is all-day. Defaults to `false`.
    /// - Returns: A fully initialised `SyncRecord`.
    private func makeSyncRecord(
        sourceId: String,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false
    ) -> SyncRecord {
        let end = endDate ?? startDate.addingTimeInterval(3600)
        let hash = ContentHasher.computeContentHash(
            startDate: startDate,
            endDate: end,
            isAllDay: isAllDay
        )
        return SyncRecord(
            sourceEventIdentifier: sourceId,
            sourceExternalIdentifier: "ext-\(sourceId)",
            sourceStartDate: startDate,
            sourceEndDate: end,
            sourceIsAllDay: isAllDay,
            sourceContentHash: hash,
            blockerEventIdentifier: "blocker-\(sourceId)",
            blockerExternalIdentifier: "blocker-ext-\(sourceId)",
            lastSyncedAt: Date()
        )
    }

    // MARK: - T035: SyncLog Computed Properties

    /// A SyncLog containing adds, removes, and updates reports correct counts
    /// via its computed properties.
    func testSyncLogSuccessProperties() {
        let added = [makeBlockerChange(), makeBlockerChange()]
        let removed = [makeBlockerChange()]
        let updated = [makeBlockerChange(), makeBlockerChange(), makeBlockerChange()]

        let log = makeSyncLog(added: added, removed: removed, updated: updated)

        XCTAssertEqual(log.addedCount, 2, "addedCount must match the number of added changes")
        XCTAssertEqual(log.removedCount, 1, "removedCount must match the number of removed changes")
        XCTAssertEqual(log.updatedCount, 3, "updatedCount must match the number of updated changes")
        XCTAssertTrue(log.isSuccess, "A log with no errors must report isSuccess == true")
    }

    /// A SyncLog containing one or more errors reports isSuccess == false.
    func testSyncLogWithErrors() {
        let error = SyncError(code: .calendarNotFound, message: "Calendar deleted")
        let log = makeSyncLog(errors: [error])

        XCTAssertFalse(log.isSuccess, "A log with errors must report isSuccess == false")
        XCTAssertEqual(log.errors.count, 1, "Error count must reflect the provided errors")
        XCTAssertEqual(log.errors.first?.code, .calendarNotFound)
    }

    /// A SyncLog with all empty arrays is still considered a success
    /// (represents a no-op sync pass with nothing to do).
    func testSyncLogEmptySync() {
        let log = makeSyncLog()

        XCTAssertEqual(log.addedCount, 0)
        XCTAssertEqual(log.removedCount, 0)
        XCTAssertEqual(log.updatedCount, 0)
        XCTAssertTrue(log.isSuccess, "An empty sync with no errors is a success")
    }

    // MARK: - T035: ContentHasher Integration (Diff Change Detection)

    /// ContentHasher must produce identical hashes for identical event data.
    /// This is the invariant the diff algorithm relies on to detect "unchanged" events.
    func testContentHashIntegration() {
        let hashA = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: fixtureEnd,
            isAllDay: false
        )
        let hashB = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: fixtureEnd,
            isAllDay: false
        )

        XCTAssertEqual(hashA, hashB, "Same event data must produce the same content hash")
        XCTAssertFalse(hashA.isEmpty, "Content hash must not be empty")
    }

    /// Changing start or end date must produce a different hash, which is how
    /// the diff algorithm detects that a source event has been rescheduled.
    func testContentHashDetectsTimeChange() {
        let original = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: fixtureEnd,
            isAllDay: false
        )

        // Shift start date by 30 minutes.
        let shiftedStart = fixtureStart.addingTimeInterval(1800)
        let withNewStart = ContentHasher.computeContentHash(
            startDate: shiftedStart,
            endDate: fixtureEnd,
            isAllDay: false
        )

        // Shift end date by 30 minutes.
        let shiftedEnd = fixtureEnd.addingTimeInterval(1800)
        let withNewEnd = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: shiftedEnd,
            isAllDay: false
        )

        XCTAssertNotEqual(original, withNewStart, "Different start date must produce a different hash")
        XCTAssertNotEqual(original, withNewEnd, "Different end date must produce a different hash")
        XCTAssertNotEqual(withNewStart, withNewEnd, "Different changes must produce distinct hashes")
    }

    /// Toggling isAllDay on the same date range must produce a different hash.
    /// The diff algorithm uses this to detect all-day vs. timed event changes.
    func testContentHashDetectsAllDayChange() {
        let timedHash = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: fixtureEnd,
            isAllDay: false
        )
        let allDayHash = ContentHasher.computeContentHash(
            startDate: fixtureStart,
            endDate: fixtureEnd,
            isAllDay: true
        )

        XCTAssertNotEqual(
            timedHash, allDayHash,
            "Toggling isAllDay must produce a different hash for the diff to detect the change"
        )
    }

    // MARK: - T036: Blocker Privacy Verification

    /// The blocker notes tag constant must match the expected value used to
    /// identify CalMirror-managed events in the target calendar.
    func testBlockerNotesTagConstant() {
        XCTAssertEqual(
            CalendarService.blockerNotesTag,
            "Managed by CalMirror",
            "blockerNotesTag must be the exact expected string"
        )
    }

    /// SyncRecord.id must be derived from sourceEventIdentifier and the
    /// integer epoch of sourceStartDate, formatted as "{id}_{epoch}".
    func testSyncRecordDerivedId() {
        let sourceId = "ABC-123"
        let startDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC

        let record = makeSyncRecord(sourceId: sourceId, startDate: startDate)

        let expectedId = "\(sourceId)_\(Int(startDate.timeIntervalSince1970))"
        XCTAssertEqual(record.id, expectedId, "SyncRecord.id must use the composite key format")
        XCTAssertEqual(record.id, "ABC-123_1700000000")
    }

    /// Two SyncRecords with the same sourceEventIdentifier but different start
    /// dates must produce different IDs. This is critical for recurring event
    /// support where each occurrence shares the same event identifier but has
    /// a unique start time.
    func testSyncRecordDerivedIdDifferentDates() {
        let sourceId = "recurring-event-1"
        let mondayStart = Date(timeIntervalSince1970: 1_736_841_600)   // 2025-01-14 08:00 UTC
        let tuesdayStart = Date(timeIntervalSince1970: 1_736_928_000)  // 2025-01-15 08:00 UTC

        let mondayRecord = makeSyncRecord(sourceId: sourceId, startDate: mondayStart)
        let tuesdayRecord = makeSyncRecord(sourceId: sourceId, startDate: tuesdayStart)

        XCTAssertNotEqual(
            mondayRecord.id, tuesdayRecord.id,
            "Same sourceEventIdentifier with different start dates must produce different IDs"
        )
        XCTAssertEqual(mondayRecord.sourceEventIdentifier, tuesdayRecord.sourceEventIdentifier,
                        "Both records share the same source event identifier")
    }

    /// BlockerChange must carry only time-boundary data (startDate, endDate, isAllDay).
    /// No source event content (title, location, attendees, notes) should leak
    /// through the blocker change. Encoding to JSON and inspecting the keys
    /// verifies that no additional stored properties exist.
    func testBlockerChangeContainsOnlyTimeData() throws {
        let change = makeBlockerChange(isAllDay: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(change)

        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys: Set<String> = decoded.map { Set($0.keys) } ?? []
        let expectedKeys: Set<String> = ["startDate", "endDate", "isAllDay"]

        XCTAssertEqual(
            keys, expectedKeys,
            "BlockerChange must encode exactly startDate, endDate, and isAllDay. Found: \(keys)"
        )
    }

    /// All SyncError.ErrorCode cases must survive a JSON encode/decode round-trip.
    /// This ensures the enum's raw values are stable for persisted sync logs.
    func testSyncErrorCodes() throws {
        let allCodes: [SyncError.ErrorCode] = [
            .calendarNotFound,
            .calendarReadOnly,
            .accessDenied,
            .eventKitInternal,
            .blockerOperationFailed,
            .unknown
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for code in allCodes {
            let error = SyncError(code: code, message: "Test message for \(code.rawValue)")
            let data = try encoder.encode(error)
            let restored = try decoder.decode(SyncError.self, from: data)

            XCTAssertEqual(
                restored.code, code,
                "ErrorCode.\(code.rawValue) must survive JSON round-trip"
            )
            XCTAssertEqual(
                restored.message, error.message,
                "Error message must survive JSON round-trip for code \(code.rawValue)"
            )
        }
    }

    // MARK: - T036: ErrorCode Raw Values Stability

    /// Verify that each ErrorCode has the expected raw string value.
    /// These raw values are serialised to JSON and changing them would break
    /// persisted sync logs.
    func testSyncErrorCodeRawValues() {
        XCTAssertEqual(SyncError.ErrorCode.calendarNotFound.rawValue, "calendarNotFound")
        XCTAssertEqual(SyncError.ErrorCode.calendarReadOnly.rawValue, "calendarReadOnly")
        XCTAssertEqual(SyncError.ErrorCode.accessDenied.rawValue, "accessDenied")
        XCTAssertEqual(SyncError.ErrorCode.eventKitInternal.rawValue, "eventKitInternal")
        XCTAssertEqual(SyncError.ErrorCode.blockerOperationFailed.rawValue, "blockerOperationFailed")
        XCTAssertEqual(SyncError.ErrorCode.unknown.rawValue, "unknown")
    }

    // MARK: - T043: SyncRecord File-Per-Rule Isolation

    /// Verifies that SyncRecordStore provides complete isolation between rules.
    ///
    /// Creates records for two independent rules (A and B), verifies that
    /// loading each rule returns only its own records, deletes records for
    /// rule A, and confirms rule B's records remain intact. This guarantees
    /// that rule deletion (cascade cleanup) cannot accidentally corrupt
    /// another rule's sync state.
    func testSyncRecordFilePerRuleIsolation() throws {
        // Set up a temporary directory for the test store.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalmMirrorTests-\(UUID().uuidString)", isDirectory: true)
        let store = try SyncRecordStore(baseDirectory: tempDir)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Define two independent rule IDs.
        let ruleAId = UUID()
        let ruleBId = UUID()

        // Create records for rule A: two events on different days.
        let recordA1 = makeSyncRecord(
            sourceId: "src-A1",
            startDate: Date(timeIntervalSince1970: 1_736_841_600)  // 2025-01-14 08:00 UTC
        )
        let recordA2 = makeSyncRecord(
            sourceId: "src-A2",
            startDate: Date(timeIntervalSince1970: 1_736_928_000)  // 2025-01-15 08:00 UTC
        )

        // Create records for rule B: three events.
        let recordB1 = makeSyncRecord(
            sourceId: "src-B1",
            startDate: Date(timeIntervalSince1970: 1_737_014_400)  // 2025-01-16 08:00 UTC
        )
        let recordB2 = makeSyncRecord(
            sourceId: "src-B2",
            startDate: Date(timeIntervalSince1970: 1_737_100_800)  // 2025-01-17 08:00 UTC
        )
        let recordB3 = makeSyncRecord(
            sourceId: "src-B3",
            startDate: Date(timeIntervalSince1970: 1_737_187_200)  // 2025-01-18 08:00 UTC
        )

        // Persist records for both rules.
        try store.saveRecords([recordA1, recordA2], for: ruleAId)
        try store.saveRecords([recordB1, recordB2, recordB3], for: ruleBId)

        // Verify rule A returns only its own records.
        let loadedA = store.loadRecords(for: ruleAId)
        XCTAssertEqual(loadedA.count, 2, "Rule A must have exactly 2 records")
        let loadedAIds = Set(loadedA.map(\.sourceEventIdentifier))
        XCTAssertTrue(loadedAIds.contains("src-A1"), "Rule A must contain record A1")
        XCTAssertTrue(loadedAIds.contains("src-A2"), "Rule A must contain record A2")
        XCTAssertFalse(loadedAIds.contains("src-B1"), "Rule A must not contain any rule B records")

        // Verify rule B returns only its own records.
        let loadedB = store.loadRecords(for: ruleBId)
        XCTAssertEqual(loadedB.count, 3, "Rule B must have exactly 3 records")
        let loadedBIds = Set(loadedB.map(\.sourceEventIdentifier))
        XCTAssertTrue(loadedBIds.contains("src-B1"), "Rule B must contain record B1")
        XCTAssertTrue(loadedBIds.contains("src-B2"), "Rule B must contain record B2")
        XCTAssertTrue(loadedBIds.contains("src-B3"), "Rule B must contain record B3")
        XCTAssertFalse(loadedBIds.contains("src-A1"), "Rule B must not contain any rule A records")

        // Delete rule A's records.
        try store.deleteRecords(for: ruleAId)

        // Verify rule A's records are gone.
        let loadedAAfterDelete = store.loadRecords(for: ruleAId)
        XCTAssertTrue(loadedAAfterDelete.isEmpty, "Rule A records must be empty after deletion")

        // Verify rule A's file no longer exists on disk.
        let ruleAFilePath = store.filePath(for: ruleAId)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ruleAFilePath.path),
            "Rule A's JSON file must not exist after deletion"
        )

        // Verify rule B's records are completely unaffected.
        let loadedBAfterDelete = store.loadRecords(for: ruleBId)
        XCTAssertEqual(loadedBAfterDelete.count, 3, "Rule B must still have exactly 3 records after deleting rule A")
        let loadedBIdsAfterDelete = Set(loadedBAfterDelete.map(\.sourceEventIdentifier))
        XCTAssertEqual(
            loadedBIdsAfterDelete, loadedBIds,
            "Rule B's records must be identical before and after deleting rule A"
        )

        // Verify rule B's file still exists on disk.
        let ruleBFilePath = store.filePath(for: ruleBId)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: ruleBFilePath.path),
            "Rule B's JSON file must still exist after deleting rule A"
        )
    }
}
