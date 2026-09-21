import XCTest
@testable import CalmMirrorCore

/// Unit tests for the duplicate-blocker protection: collapsing source events
/// that would yield identical blockers, and matching blockers by title and time.
final class BlockerDeduplicatorTests: XCTestCase {

    // MARK: - Fixtures

    /// Minimal stand-in for a source event: the blocker hash it produces and
    /// whether a sync record already mirrors it.
    private struct Candidate: Equatable {
        let name: String
        let hash: String
        let mirrored: Bool
    }

    private func collapse(_ candidates: [Candidate]) -> [String] {
        BlockerDeduplicator.collapseDuplicates(
            candidates,
            blockerKey: \.hash,
            isAlreadyMirrored: \.mirrored
        ).map(\.name)
    }

    private let start = Date(timeIntervalSince1970: 1_736_931_600)
    private let end = Date(timeIntervalSince1970: 1_736_935_200)

    // MARK: - collapseDuplicates

    /// Events producing distinct blockers are all kept, in their original order.
    func testDistinctEventsAreAllKept() {
        let result = collapse([
            Candidate(name: "a", hash: "h1", mirrored: false),
            Candidate(name: "b", hash: "h2", mirrored: true),
            Candidate(name: "c", hash: "h3", mirrored: false),
        ])
        XCTAssertEqual(result, ["a", "b", "c"])
    }

    /// Two new source events with the same title and time yield a single blocker.
    func testDuplicateNewEventsCollapseToFirst() {
        let result = collapse([
            Candidate(name: "a", hash: "same", mirrored: false),
            Candidate(name: "b", hash: "same", mirrored: false),
        ])
        XCTAssertEqual(result, ["a"])
    }

    /// The already-mirrored event wins, so its existing blocker is reused
    /// instead of being deleted and recreated.
    func testAlreadyMirroredEventIsPreferred() {
        let result = collapse([
            Candidate(name: "new", hash: "same", mirrored: false),
            Candidate(name: "known", hash: "same", mirrored: true),
        ])
        XCTAssertEqual(result, ["known"])
    }

    /// When several duplicates are already mirrored (pre-existing duplicate
    /// blockers), only the first is kept so the others get cleaned up as orphans.
    func testSeveralMirroredDuplicatesKeepOnlyFirst() {
        let result = collapse([
            Candidate(name: "known1", hash: "same", mirrored: true),
            Candidate(name: "other", hash: "other", mirrored: true),
            Candidate(name: "known2", hash: "same", mirrored: true),
        ])
        XCTAssertEqual(result, ["known1", "other"])
    }

    func testEmptyInput() {
        XCTAssertEqual(collapse([]), [])
    }

    // MARK: - BlockerKey

    /// Same title and time match even when sub-second precision differs
    /// (EventKit may truncate dates on save).
    func testBlockerKeyIgnoresSubSecondDifferences() {
        let a = BlockerKey(title: "[CMA] Daily", startDate: start, endDate: end, isAllDay: false)
        let b = BlockerKey(
            title: "[CMA] Daily",
            startDate: start.addingTimeInterval(0.4),
            endDate: end.addingTimeInterval(0.4),
            isAllDay: false
        )
        XCTAssertEqual(a, b)
    }

    /// Any difference in title, time or all-day flag makes a different blocker.
    func testBlockerKeyDistinguishesTitleTimeAndAllDay() {
        let base = BlockerKey(title: "Busy", startDate: start, endDate: end, isAllDay: false)
        XCTAssertNotEqual(base, BlockerKey(title: "Other", startDate: start, endDate: end, isAllDay: false))
        XCTAssertNotEqual(base, BlockerKey(title: "Busy", startDate: start.addingTimeInterval(60), endDate: end, isAllDay: false))
        XCTAssertNotEqual(base, BlockerKey(title: "Busy", startDate: start, endDate: end.addingTimeInterval(60), isAllDay: false))
        XCTAssertNotEqual(base, BlockerKey(title: "Busy", startDate: start, endDate: end, isAllDay: true))
    }
}
