import XCTest
@testable import CalmMirrorCore

/// Unit tests for the `MirrorRule` model covering initialization defaults,
/// input validation, boundary conditions, and Codable round-trip fidelity.
final class MirrorRuleTests: XCTestCase {

    // MARK: - Test Data

    private let validTitle = "Work Mirror"
    private let validSource = "source-calendar-id"
    private let validTarget = "target-calendar-id"
    private let validWindowDays = 14
    private let validLabel = "Busy"

    // MARK: - Initialization

    /// Verify the convenience initializer sets expected default values:
    /// a fresh UUID, `isEnabled = true`, and `createdAt` / `updatedAt` close to now.
    func testValidRuleCreation() {
        let before = Date()
        let rule = MirrorRule(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel
        )
        let after = Date()

        XCTAssertEqual(rule.title, validTitle)
        XCTAssertEqual(rule.sourceCalendarIdentifier, validSource)
        XCTAssertEqual(rule.targetCalendarIdentifier, validTarget)
        XCTAssertEqual(rule.windowDays, validWindowDays)
        XCTAssertEqual(rule.blockerLabel, validLabel)
        XCTAssertTrue(rule.isEnabled, "Newly created rule should be enabled by default")
        XCTAssertFalse(rule.id.uuidString.isEmpty, "UUID should be assigned")

        // Timestamps should fall within the test execution window.
        XCTAssertGreaterThanOrEqual(rule.createdAt, before)
        XCTAssertLessThanOrEqual(rule.createdAt, after)
        XCTAssertEqual(
            rule.createdAt,
            rule.updatedAt,
            "createdAt and updatedAt should be identical on creation"
        )
    }

    // MARK: - Validation — Happy Path

    /// Validate returns `nil` when all parameters satisfy the business rules.
    func testValidationPassesForValidInput() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel
        )
        XCTAssertNil(error, "Valid input should produce no validation error")
    }

    // MARK: - Validation — Title

    /// An empty title must return `.emptyTitle`.
    func testEmptyTitleValidation() {
        let error = MirrorRule.validate(
            title: "",
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel
        )
        XCTAssertEqual(error, .emptyTitle)
    }

    /// A whitespace-only title must return `.emptyTitle` (trimmed check).
    func testWhitespaceOnlyTitleValidation() {
        let error = MirrorRule.validate(
            title: "   ",
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel
        )
        XCTAssertEqual(error, .emptyTitle)
    }

    // MARK: - Validation — Self-Mirroring

    /// Source and target pointing to the same calendar must return `.selfMirroring`.
    func testSelfMirroringValidation() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validSource,
            windowDays: validWindowDays,
            blockerLabel: validLabel
        )
        XCTAssertEqual(error, .selfMirroring)
    }

    // MARK: - Validation — Window Days

    /// A window below the minimum (< 1) must return `.windowOutOfRange`.
    func testWindowTooLow() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: 0,
            blockerLabel: validLabel
        )
        XCTAssertEqual(error, .windowOutOfRange)
    }

    /// A window above the maximum (> 120) must return `.windowOutOfRange`.
    func testWindowTooHigh() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: 121,
            blockerLabel: validLabel
        )
        XCTAssertEqual(error, .windowOutOfRange)
    }

    /// The lower boundary (1 day) is within the valid range.
    func testWindowBoundaryLow() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: 1,
            blockerLabel: validLabel
        )
        XCTAssertNil(error, "windowDays == 1 is the lower boundary and should be valid")
    }

    /// The upper boundary (120 days) is within the valid range.
    func testWindowBoundaryHigh() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: 120,
            blockerLabel: validLabel
        )
        XCTAssertNil(error, "windowDays == 120 is the upper boundary and should be valid")
    }

    // MARK: - Validation — Blocker Label

    /// An empty string label must return `.emptyLabel`.
    func testEmptyLabelValidation() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: ""
        )
        XCTAssertEqual(error, .emptyLabel)
    }

    /// A whitespace-only label must return `.emptyLabel` (trimmed check).
    func testWhitespaceOnlyLabelValidation() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "   "
        )
        XCTAssertEqual(error, .emptyLabel)
    }

    // MARK: - Codable Round-Trip

    /// Encoding a `MirrorRule` to JSON and decoding it back must produce an
    /// identical instance — every property must survive the round trip.
    func testCodableRoundTrip() throws {
        let original = MirrorRule(
            id: UUID(),
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel,
            isEnabled: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MirrorRule.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.sourceCalendarIdentifier, original.sourceCalendarIdentifier)
        XCTAssertEqual(decoded.targetCalendarIdentifier, original.targetCalendarIdentifier)
        XCTAssertEqual(decoded.windowDays, original.windowDays)
        XCTAssertEqual(decoded.blockerLabel, original.blockerLabel)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(
            decoded.createdAt.timeIntervalSince1970,
            original.createdAt.timeIntervalSince1970,
            accuracy: 0.001,
            "createdAt must survive JSON round trip"
        )
        XCTAssertEqual(
            decoded.updatedAt.timeIntervalSince1970,
            original.updatedAt.timeIntervalSince1970,
            accuracy: 0.001,
            "updatedAt must survive JSON round trip"
        )
    }

    // MARK: - Backward-Compatible Decoding

    /// Decoding a rule without a `title` field should default to `blockerLabel`.
    ///
    /// This ensures existing rules persisted before the `title` property was
    /// introduced remain readable and display the blocker label as fallback.
    func testBackwardCompatibleDecodingWithoutTitle() throws {
        // JSON payload without the "title" key, simulating a pre-existing rule.
        let jsonString = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "sourceCalendarIdentifier": "\(validSource)",
            "targetCalendarIdentifier": "\(validTarget)",
            "windowDays": \(validWindowDays),
            "blockerLabel": "\(validLabel)",
            "isEnabled": true,
            "createdAt": 1700000000,
            "updatedAt": 1700001000
        }
        """
        let data = Data(jsonString.utf8)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MirrorRule.self, from: data)

        XCTAssertEqual(
            decoded.title,
            validLabel,
            "title should default to blockerLabel when absent from JSON"
        )
        XCTAssertEqual(decoded.blockerLabel, validLabel)
    }
}
