import XCTest
@testable import CalmMirrorCore

final class ChainingPolicyTests: XCTestCase {
    private func rule(_ source: String, _ target: String, chaining: Bool = false) -> MirrorRule {
        MirrorRule(title: "Test", sourceCalendarIdentifier: source,
                   targetCalendarIdentifier: target, windowDays: 30,
                   blockerLabel: "Busy", allowChaining: chaining)
    }

    func testSixRulesOnlyPropagateOriginalEvents() {
        let rules = [rule("personal", "work1"), rule("personal", "work2"),
                     rule("family", "work1"), rule("family", "work2"),
                     rule("work1", "personal"), rule("work2", "personal")]
        let expected: [String: Set<String>] = [
            "personal": ["work1", "work2"], "family": ["work1", "work2"],
            "work1": ["personal"], "work2": ["personal"]
        ]
        for (source, destinations) in expected {
            var reached = Set<String>()
            var pending: [(String, String?)] = [(source, nil)]
            while !pending.isEmpty {
                let (calendar, notes) = pending.removeFirst()
                for rule in rules where rule.sourceCalendarIdentifier == calendar {
                    guard rule.acceptsSource(notes: notes) else { continue }
                    reached.insert(rule.targetCalendarIdentifier)
                    pending.append((rule.targetCalendarIdentifier, BlockerNotes.compose(origins:
                        BlockerNotes.originsForBlocker(sourceNotes: notes, sourceCalendarIdentifier: calendar))))
                }
            }
            XCTAssertEqual(reached, destinations, "Unexpected propagation from \(source)")
        }
    }

    func testOptInAllowsChainsButStillStopsLoops() {
        let notes = BlockerNotes.compose(origins: ["work1"])
        XCTAssertTrue(rule("personal", "work2", chaining: true).acceptsSource(notes: notes))
        XCTAssertFalse(rule("personal", "work1", chaining: true).acceptsSource(notes: notes))
    }

    func testLegacyBlockersAreExcludedWithoutRequiringOrigins() {
        XCTAssertFalse(rule("personal", "work1").acceptsSource(notes: "Managed by CalMirror"))
        XCTAssertTrue(rule("personal", "work1").acceptsSource(notes: "Meeting notes"))
    }

    func testPolicyPersistsAndOldRulesKeepChaining() throws {
        for enabled in [true, false] {
            let original = rule("personal", "work1", chaining: enabled)
            let data = try JSONEncoder().encode(original)
            XCTAssertEqual(try JSONDecoder().decode(MirrorRule.self, from: data).allowChaining, enabled)
        }
        let data = try JSONEncoder().encode(rule("personal", "work1"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "allowChaining")
        let legacy = try JSONDecoder().decode(MirrorRule.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.allowChaining)
    }
}
