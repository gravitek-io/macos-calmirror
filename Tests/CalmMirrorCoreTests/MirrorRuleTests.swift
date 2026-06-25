import XCTest
@testable import CalmMirrorCore

/// Unit tests for the `MirrorRule` model covering initialization defaults,
/// input validation, boundary conditions, Codable round-trip fidelity, and
/// blocker title derivation (source-name vs. placeholder mode).
final class MirrorRuleTests: XCTestCase {

    // MARK: - Test Data

    private let validTitle = "Work Mirror"
    private let validSource = "source-calendar-id"
    private let validTarget = "target-calendar-id"
    private let validWindowDays = 14
    private let validLabel = "Busy"

    // MARK: - Initialization

    /// Verify the convenience initializer sets expected default values:
    /// a fresh UUID, `isEnabled = true`, `usePlaceholder = false` (new default:
    /// mirror the source event name), and timestamps close to now.
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
        XCTAssertFalse(
            rule.usePlaceholder,
            "New rules should default to source-name mode (usePlaceholder == false)"
        )
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

    // MARK: - Blocker Title Derivation

    /// In source-name mode the blocker title is the rule title prefix followed
    /// by the source event name.
    func testBlockerTitleUsesSourceNameByDefault() {
        let rule = MirrorRule(
            title: "Acme",
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "Busy"
        )
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: "Tax meeting"), "[Acme] Tax meeting")
    }

    /// In source-name mode an empty source title falls back to "(No title)".
    func testBlockerTitleFallsBackForEmptySourceTitle() {
        let rule = MirrorRule(
            title: "Acme",
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "Busy"
        )
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: ""), "[Acme] (No title)")
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: "   "), "[Acme] (No title)")
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: nil), "[Acme] (No title)")
    }

    /// In placeholder mode the blocker title is the static label, regardless of
    /// the source event name.
    func testBlockerTitleUsesPlaceholderWhenEnabled() {
        let rule = MirrorRule(
            id: UUID(),
            title: "Acme",
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "[Acme] Busy",
            usePlaceholder: true,
            isEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: "Tax meeting"), "[Acme] Busy")
        XCTAssertEqual(rule.blockerTitle(forSourceTitle: ""), "[Acme] Busy")
    }

    // MARK: - Validation — Happy Path

    /// Validate returns `nil` when all parameters satisfy the business rules.
    func testValidationPassesForValidInput() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
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
            blockerLabel: validLabel,
            usePlaceholder: true
        )
        XCTAssertNil(error, "windowDays == 120 is the upper boundary and should be valid")
    }

    // MARK: - Validation — Blocker Label

    /// An empty label must return `.emptyLabel` when placeholder mode is enabled.
    func testEmptyLabelValidationInPlaceholderMode() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "",
            usePlaceholder: true
        )
        XCTAssertEqual(error, .emptyLabel)
    }

    /// A whitespace-only label must return `.emptyLabel` in placeholder mode.
    func testWhitespaceOnlyLabelValidationInPlaceholderMode() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "   ",
            usePlaceholder: true
        )
        XCTAssertEqual(error, .emptyLabel)
    }

    /// An empty label is accepted in source-name mode, where the label is unused.
    func testEmptyLabelAllowedInSourceNameMode() {
        let error = MirrorRule.validate(
            title: validTitle,
            sourceCalendarIdentifier: validSource,
            targetCalendarIdentifier: validTarget,
            windowDays: validWindowDays,
            blockerLabel: "",
            usePlaceholder: false
        )
        XCTAssertNil(error, "Empty label is harmless when not using the placeholder")
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
            usePlaceholder: true,
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
        XCTAssertEqual(decoded.usePlaceholder, original.usePlaceholder)
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

    /// Decoding a rule without `usePlaceholder` must default to `true`, preserving
    /// the static-label behavior of rules created before this field existed.
    /// New rules opt into source-name mode; existing rules must not silently start
    /// leaking source event titles.
    func testBackwardCompatibleDecodingWithoutUsePlaceholder() throws {
        let jsonString = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "title": "Legacy Rule",
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

        XCTAssertTrue(
            decoded.usePlaceholder,
            "Legacy rules without usePlaceholder must preserve static-label behavior"
        )
        XCTAssertEqual(
            decoded.blockerTitle(forSourceTitle: "Secret meeting"),
            validLabel,
            "Legacy rule must keep using its static label, not the source title"
        )
    }
}
