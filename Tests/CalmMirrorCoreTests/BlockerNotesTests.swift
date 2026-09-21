import XCTest
@testable import CalmMirrorCore

/// Unit tests for the blocker notes format and the mirror-loop protection
/// built on it (two-way rules A→B + B→A, and longer cycles).
final class BlockerNotesTests: XCTestCase {

    // MARK: - Compose / parse

    func testComposedNotesCarryTheManagedTag() {
        let notes = BlockerNotes.compose(origins: ["cal-A"])
        XCTAssertTrue(notes.contains(CalendarService.blockerNotesTag))
        XCTAssertTrue(BlockerNotes.isManaged(notes))
    }

    func testOriginsRoundTripInOrder() {
        let notes = BlockerNotes.compose(origins: ["cal-A", "cal-B"])
        XCTAssertEqual(BlockerNotes.origins(fromNotes: notes), ["cal-A", "cal-B"])
    }

    /// Blockers created before origins were recorded carry only the tag.
    func testLegacyBlockerHasNoOrigins() {
        XCTAssertEqual(BlockerNotes.origins(fromNotes: CalendarService.blockerNotesTag), [])
    }

    /// Origins are trusted only on CalMirror blockers, never on user events.
    func testUntaggedNotesYieldNoOrigins() {
        XCTAssertEqual(BlockerNotes.origins(fromNotes: "Origins: cal-A"), [])
        XCTAssertEqual(BlockerNotes.origins(fromNotes: nil), [])
        XCTAssertFalse(BlockerNotes.isManaged(nil))
    }

    /// Calendar servers may rewrite line endings or append text to the notes.
    func testParsingToleratesServerRewrites() {
        let notes = "Managed by CalMirror\r\nOrigins:  cal-A , cal-B \r\n\r\nAdded by server"
        XCTAssertEqual(BlockerNotes.origins(fromNotes: notes), ["cal-A", "cal-B"])
    }

    // MARK: - Origin chain

    /// A regular source event originates from its own calendar.
    func testOriginsForRegularEvent() {
        XCTAssertEqual(
            BlockerNotes.originsForBlocker(sourceNotes: "Agenda: roadmap", sourceCalendarIdentifier: "cal-A"),
            ["cal-A"]
        )
    }

    /// Mirroring a blocker (chained rules) extends its origin chain.
    func testOriginsExtendAlongAChain() {
        let blockerInB = BlockerNotes.compose(origins: ["cal-A"])
        XCTAssertEqual(
            BlockerNotes.originsForBlocker(sourceNotes: blockerInB, sourceCalendarIdentifier: "cal-B"),
            ["cal-A", "cal-B"]
        )
    }

    func testOriginsNeverRepeatACalendar() {
        let notes = BlockerNotes.compose(origins: ["cal-A", "cal-B"])
        XCTAssertEqual(
            BlockerNotes.originsForBlocker(sourceNotes: notes, sourceCalendarIdentifier: "cal-B"),
            ["cal-A", "cal-B"]
        )
    }

    // MARK: - Loop detection

    /// Two-way sync (issue #12): the blocker made by A→B must not come back to A.
    func testBlockerIsNotMirroredBackToItsOrigin() {
        let blockerInB = BlockerNotes.compose(origins: ["cal-A"])
        XCTAssertTrue(BlockerNotes.wouldLoop(sourceNotes: blockerInB, targetCalendarIdentifier: "cal-A"))
    }

    /// Chained rules (A→B then B→C) keep working: C is not an origin.
    func testChainedMirroringIsAllowed() {
        let blockerInB = BlockerNotes.compose(origins: ["cal-A"])
        XCTAssertFalse(BlockerNotes.wouldLoop(sourceNotes: blockerInB, targetCalendarIdentifier: "cal-C"))
    }

    /// Longer cycle A→B→C→A is cut when reaching A again.
    func testThreeCalendarCycleIsCut() {
        let blockerInC = BlockerNotes.compose(origins: ["cal-A", "cal-B"])
        XCTAssertTrue(BlockerNotes.wouldLoop(sourceNotes: blockerInC, targetCalendarIdentifier: "cal-A"))
    }

    func testRegularEventsNeverLoop() {
        XCTAssertFalse(BlockerNotes.wouldLoop(sourceNotes: nil, targetCalendarIdentifier: "cal-A"))
        XCTAssertFalse(BlockerNotes.wouldLoop(sourceNotes: "Origins: cal-A", targetCalendarIdentifier: "cal-A"))
    }

    // MARK: - Content hash

    /// Origins are part of the blocker's desired state, so recording them on
    /// existing blockers (or a chain change) is detected as an update.
    func testContentHashCoversOrigins() {
        let start = Date(timeIntervalSince1970: 1_736_931_600)
        let end = Date(timeIntervalSince1970: 1_736_935_200)
        let legacy = ContentHasher.computeContentHash(startDate: start, endDate: end, isAllDay: false, blockerTitle: "Busy")
        let withA = ContentHasher.computeContentHash(startDate: start, endDate: end, isAllDay: false, blockerTitle: "Busy", origins: ["cal-A"])
        let withAB = ContentHasher.computeContentHash(startDate: start, endDate: end, isAllDay: false, blockerTitle: "Busy", origins: ["cal-A", "cal-B"])
        XCTAssertNotEqual(legacy, withA)
        XCTAssertNotEqual(withA, withAB)
    }
}
