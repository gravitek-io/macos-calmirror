import XCTest
@testable import CalmMirrorCore

/// Unit tests for `SyncRecordStore` (T019).
///
/// Validates file-based persistence of sync records, including round-trip
/// serialization, per-rule file isolation, deletion behavior, and path layout.
/// All tests use a temporary directory to avoid polluting the real app support path.
final class SyncRecordStoreTests: XCTestCase {

    // MARK: - Properties

    /// Unique temporary directory created for each test case.
    private var tempDirectory: URL!

    /// Store under test, backed by `tempDirectory`.
    private var store: SyncRecordStore!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecordStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = try SyncRecordStore(baseDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        // Remove the entire temporary directory tree after each test.
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        store = nil
        tempDirectory = nil

        try super.tearDownWithError()
    }

    // MARK: - Tests

    /// Loading records for a rule that has never been saved must return an empty array.
    func testLoadReturnsEmptyForNewRule() {
        let ruleId = UUID()
        let records = store.loadRecords(for: ruleId)

        XCTAssertTrue(records.isEmpty, "Expected empty array for a rule with no persisted file")
    }

    /// Records saved for a rule must be recoverable with identical field values.
    func testSaveAndLoadRoundTrip() throws {
        let ruleId = UUID()
        let original = [
            makeSyncRecord(sourceEventIdentifier: "evt-1", blockerEventIdentifier: "blk-1"),
            makeSyncRecord(sourceEventIdentifier: "evt-2", blockerEventIdentifier: "blk-2")
        ]

        try store.saveRecords(original, for: ruleId)
        let loaded = store.loadRecords(for: ruleId)

        XCTAssertEqual(loaded.count, original.count, "Loaded record count must match saved count")

        for (saved, restored) in zip(original, loaded) {
            XCTAssertEqual(restored.sourceEventIdentifier, saved.sourceEventIdentifier)
            XCTAssertEqual(restored.sourceExternalIdentifier, saved.sourceExternalIdentifier)
            XCTAssertEqual(
                restored.sourceStartDate.timeIntervalSince1970,
                saved.sourceStartDate.timeIntervalSince1970,
                accuracy: 1.0,
                "Start dates must round-trip within 1 second (ISO 8601 precision)"
            )
            XCTAssertEqual(
                restored.sourceEndDate.timeIntervalSince1970,
                saved.sourceEndDate.timeIntervalSince1970,
                accuracy: 1.0,
                "End dates must round-trip within 1 second (ISO 8601 precision)"
            )
            XCTAssertEqual(restored.sourceIsAllDay, saved.sourceIsAllDay)
            XCTAssertEqual(restored.sourceContentHash, saved.sourceContentHash)
            XCTAssertEqual(restored.blockerEventIdentifier, saved.blockerEventIdentifier)
            XCTAssertEqual(restored.blockerExternalIdentifier, saved.blockerExternalIdentifier)
            XCTAssertEqual(
                restored.lastSyncedAt.timeIntervalSince1970,
                saved.lastSyncedAt.timeIntervalSince1970,
                accuracy: 1.0,
                "lastSyncedAt must round-trip within 1 second (ISO 8601 precision)"
            )
        }
    }

    /// Records saved under different rule IDs must be isolated in separate files.
    /// Loading one rule must not return records from another rule.
    func testFilePerRuleIsolation() throws {
        let ruleA = UUID()
        let ruleB = UUID()

        let recordsA = [makeSyncRecord(sourceEventIdentifier: "rule-a-evt")]
        let recordsB = [
            makeSyncRecord(sourceEventIdentifier: "rule-b-evt-1"),
            makeSyncRecord(sourceEventIdentifier: "rule-b-evt-2")
        ]

        try store.saveRecords(recordsA, for: ruleA)
        try store.saveRecords(recordsB, for: ruleB)

        let loadedA = store.loadRecords(for: ruleA)
        let loadedB = store.loadRecords(for: ruleB)

        XCTAssertEqual(loadedA.count, 1, "Rule A must have exactly 1 record")
        XCTAssertEqual(loadedA.first?.sourceEventIdentifier, "rule-a-evt")

        XCTAssertEqual(loadedB.count, 2, "Rule B must have exactly 2 records")
        XCTAssertEqual(loadedB.first?.sourceEventIdentifier, "rule-b-evt-1")
        XCTAssertEqual(loadedB.last?.sourceEventIdentifier, "rule-b-evt-2")
    }

    /// Deleting records for a rule must remove the file so subsequent loads return empty.
    func testDeleteRecords() throws {
        let ruleId = UUID()
        let records = [makeSyncRecord()]

        try store.saveRecords(records, for: ruleId)
        XCTAssertFalse(store.loadRecords(for: ruleId).isEmpty, "Precondition: records must exist before delete")

        try store.deleteRecords(for: ruleId)
        let loaded = store.loadRecords(for: ruleId)

        XCTAssertTrue(loaded.isEmpty, "Loading after delete must return an empty array")
    }

    /// Deleting records for a rule that has no persisted file must not throw.
    func testDeleteNonExistentFileDoesNotThrow() {
        let ruleId = UUID()

        XCTAssertNoThrow(
            try store.deleteRecords(for: ruleId),
            "Deleting a non-existent file must be a no-op without throwing"
        )
    }

    /// The file path returned for a rule must include the rule's UUID string and the `.json` extension.
    func testFilePath() {
        let ruleId = UUID()
        let path = store.filePath(for: ruleId)

        XCTAssertTrue(
            path.lastPathComponent.contains(ruleId.uuidString),
            "File path must contain the rule UUID: \(path.lastPathComponent)"
        )
        XCTAssertEqual(
            path.pathExtension, "json",
            "File path must have a .json extension"
        )
    }

    /// After a successful save the JSON file must exist on disk.
    func testAtomicWrite() throws {
        let ruleId = UUID()
        let records = [makeSyncRecord()]

        try store.saveRecords(records, for: ruleId)

        let fileURL = store.filePath(for: ruleId)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "JSON file must exist on disk after a successful save"
        )
    }

    // MARK: - Helpers

    /// Creates a `SyncRecord` with sensible defaults for testing.
    ///
    /// Override individual parameters when specific field values matter for the test.
    ///
    /// - Parameters:
    ///   - sourceEventIdentifier: Defaults to `"source-event-id"`.
    ///   - sourceExternalIdentifier: Defaults to `"source-external-id"`.
    ///   - sourceStartDate: Defaults to 2024-01-31 09:00:00 UTC.
    ///   - sourceEndDate: Defaults to 2024-01-31 10:00:00 UTC.
    ///   - sourceIsAllDay: Defaults to `false`.
    ///   - sourceContentHash: Defaults to `"abc123hash"`.
    ///   - blockerEventIdentifier: Defaults to `"blocker-event-id"`.
    ///   - blockerExternalIdentifier: Defaults to `"blocker-external-id"`.
    ///   - lastSyncedAt: Defaults to 2024-01-31 10:30:00 UTC.
    /// - Returns: A fully populated `SyncRecord`.
    private func makeSyncRecord(
        sourceEventIdentifier: String = "source-event-id",
        sourceExternalIdentifier: String = "source-external-id",
        sourceStartDate: Date = Date(timeIntervalSince1970: 1_706_688_000),   // 2024-01-31 09:00 UTC
        sourceEndDate: Date = Date(timeIntervalSince1970: 1_706_691_600),     // 2024-01-31 10:00 UTC
        sourceIsAllDay: Bool = false,
        sourceContentHash: String = "abc123hash",
        blockerEventIdentifier: String = "blocker-event-id",
        blockerExternalIdentifier: String = "blocker-external-id",
        lastSyncedAt: Date = Date(timeIntervalSince1970: 1_706_693_400)       // 2024-01-31 10:30 UTC
    ) -> SyncRecord {
        SyncRecord(
            sourceEventIdentifier: sourceEventIdentifier,
            sourceExternalIdentifier: sourceExternalIdentifier,
            sourceStartDate: sourceStartDate,
            sourceEndDate: sourceEndDate,
            sourceIsAllDay: sourceIsAllDay,
            sourceContentHash: sourceContentHash,
            blockerEventIdentifier: blockerEventIdentifier,
            blockerExternalIdentifier: blockerExternalIdentifier,
            lastSyncedAt: lastSyncedAt
        )
    }
}
