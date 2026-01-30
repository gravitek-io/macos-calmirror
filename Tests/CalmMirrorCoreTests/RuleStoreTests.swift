import XCTest
@testable import CalmMirrorCore

/// Unit tests for `RuleStore` CRUD operations.
///
/// Each test creates an isolated `UserDefaults` instance via a unique suite name
/// to guarantee test independence. The suite is removed in `tearDown` to avoid
/// polluting the system preferences on the test runner.
final class RuleStoreTests: XCTestCase {

    // MARK: - Properties

    /// Unique suite name regenerated for every test method.
    private var suiteName: String!

    /// Isolated UserDefaults used by the store under test.
    private var testDefaults: UserDefaults!

    /// The store instance under test.
    private var store: RuleStore!

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        suiteName = "test.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = RuleStore(defaults: testDefaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a valid `MirrorRule` with distinct source/target calendars.
    private func makeRule(
        id: UUID = UUID(),
        source: String = "source-calendar",
        target: String = "target-calendar",
        windowDays: Int = 14,
        label: String = "Busy",
        isEnabled: Bool = true
    ) -> MirrorRule {
        let now = Date()
        return MirrorRule(
            id: id,
            sourceCalendarIdentifier: source,
            targetCalendarIdentifier: target,
            windowDays: windowDays,
            blockerLabel: label,
            isEnabled: isEnabled,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Tests

    /// T018-1: A freshly created store with no prior data returns an empty array.
    func testLoadRulesEmptyByDefault() {
        let rules = store.loadRules()
        XCTAssertTrue(rules.isEmpty, "Expected no rules in a fresh UserDefaults instance")
    }

    /// T018-2: Adding a valid rule persists it so that subsequent loads return it.
    func testAddAndLoadRule() throws {
        let rule = makeRule()
        try store.addRule(rule)

        let loaded = store.loadRules()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, rule.id)
        XCTAssertEqual(loaded.first?.sourceCalendarIdentifier, rule.sourceCalendarIdentifier)
        XCTAssertEqual(loaded.first?.targetCalendarIdentifier, rule.targetCalendarIdentifier)
        XCTAssertEqual(loaded.first?.windowDays, rule.windowDays)
        XCTAssertEqual(loaded.first?.blockerLabel, rule.blockerLabel)
    }

    /// T018-3: Adding a rule whose source and target are the same throws `selfMirroring`.
    func testAddRuleValidationRejectsSelfMirroring() {
        let rule = makeRule(source: "same-calendar", target: "same-calendar")

        XCTAssertThrowsError(try store.addRule(rule)) { error in
            guard let validationError = error as? MirrorRule.ValidationError else {
                return XCTFail("Expected MirrorRule.ValidationError, got \(type(of: error))")
            }
            XCTAssertEqual(validationError, .selfMirroring)
        }
        XCTAssertTrue(store.loadRules().isEmpty, "Invalid rule should not be persisted")
    }

    /// T018-4: Adding a rule with windowDays outside 1...120 throws `windowOutOfRange`.
    func testAddRuleValidationRejectsInvalidWindow() {
        let ruleZero = makeRule(windowDays: 0)

        XCTAssertThrowsError(try store.addRule(ruleZero)) { error in
            guard let validationError = error as? MirrorRule.ValidationError else {
                return XCTFail("Expected MirrorRule.ValidationError, got \(type(of: error))")
            }
            XCTAssertEqual(validationError, .windowOutOfRange)
        }
        XCTAssertTrue(store.loadRules().isEmpty, "Invalid rule should not be persisted")
    }

    /// T018-5: Adding a rule with an empty (or whitespace-only) label throws `emptyLabel`.
    func testAddRuleValidationRejectsEmptyLabel() {
        let rule = makeRule(label: "   ")

        XCTAssertThrowsError(try store.addRule(rule)) { error in
            guard let validationError = error as? MirrorRule.ValidationError else {
                return XCTFail("Expected MirrorRule.ValidationError, got \(type(of: error))")
            }
            XCTAssertEqual(validationError, .emptyLabel)
        }
        XCTAssertTrue(store.loadRules().isEmpty, "Invalid rule should not be persisted")
    }

    /// T018-6: Removing an existing rule leaves the store empty.
    func testRemoveRule() throws {
        let rule = makeRule()
        try store.addRule(rule)
        XCTAssertEqual(store.loadRules().count, 1)

        let removed = try store.removeRule(id: rule.id)
        XCTAssertEqual(removed.id, rule.id, "Returned rule should match the one removed")
        XCTAssertTrue(store.loadRules().isEmpty, "Store should be empty after removing the only rule")
    }

    /// T018-7: Removing a rule with an unknown UUID throws `ruleNotFound`.
    func testRemoveNonExistentRuleThrows() {
        let unknownID = UUID()

        XCTAssertThrowsError(try store.removeRule(id: unknownID)) { error in
            guard let storeError = error as? RuleStoreError else {
                return XCTFail("Expected RuleStoreError, got \(type(of: error))")
            }
            guard case .ruleNotFound(let id) = storeError else {
                return XCTFail("Expected ruleNotFound, got \(storeError)")
            }
            XCTAssertEqual(id, unknownID)
        }
    }

    /// T018-8: Disabling then re-enabling a rule toggles `isEnabled` correctly.
    func testEnableDisableRule() throws {
        let rule = makeRule(isEnabled: true)
        try store.addRule(rule)

        // Disable
        try store.disableRule(id: rule.id)
        let disabled = store.rule(for: rule.id)
        XCTAssertNotNil(disabled)
        XCTAssertFalse(disabled!.isEnabled, "Rule should be disabled")

        // Re-enable
        try store.enableRule(id: rule.id)
        let enabled = store.rule(for: rule.id)
        XCTAssertNotNil(enabled)
        XCTAssertTrue(enabled!.isEnabled, "Rule should be enabled again")
    }

    /// T018-9: Updating a rule persists the changed fields while preserving identity.
    func testUpdateRule() throws {
        var rule = makeRule(windowDays: 14)
        try store.addRule(rule)

        rule.windowDays = 30
        try store.updateRule(rule)

        let loaded = store.rule(for: rule.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.windowDays, 30, "windowDays should reflect the updated value")
    }

    /// T018-10: Looking up a rule by id returns the correct one among multiple stored rules.
    func testRuleForId() throws {
        let ruleA = makeRule(source: "cal-A", target: "cal-B", label: "Meeting")
        let ruleB = makeRule(source: "cal-C", target: "cal-D", label: "Focus")
        try store.addRule(ruleA)
        try store.addRule(ruleB)

        let found = store.rule(for: ruleB.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found!.id, ruleB.id)
        XCTAssertEqual(found!.blockerLabel, "Focus")

        let notFound = store.rule(for: UUID())
        XCTAssertNil(notFound, "Looking up a non-existent id should return nil")
    }

    /// T018-11: Data written by one `RuleStore` instance is readable from another instance
    /// that shares the same underlying `UserDefaults`.
    func testPersistenceAcrossInstances() throws {
        let rule = makeRule(label: "Cross-instance")
        try store.addRule(rule)

        // Create a second store backed by the same UserDefaults suite
        let secondStore = RuleStore(defaults: testDefaults)
        let loaded = secondStore.loadRules()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, rule.id)
        XCTAssertEqual(loaded.first?.blockerLabel, "Cross-instance")
    }
}
