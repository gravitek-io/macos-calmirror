import Foundation

/// Reads and writes the notes field of CalMirror blockers.
///
/// A blocker's notes hold the ``CalendarService/blockerNotesTag`` line followed
/// by an `Origins:` line listing the identifiers of every calendar the blocker
/// derives from, oldest first:
///
/// ```text
/// Managed by CalMirror
/// Origins: <calendar A id>, <calendar B id>
/// ```
///
/// The origin chain is what prevents mirror loops. With two rules A→B and B→A,
/// the blocker created in B would otherwise be mirrored back into A, then into
/// B again, and so on. Because rules can legitimately be chained (A→B, B→C),
/// blockers cannot simply be ignored as source events; instead a blocker is
/// only refused when the rule's target calendar is one of its origins.
///
/// Calendar identifiers are opaque local UUIDs: they reveal nothing about the
/// source events. Storing the chain on the event itself keeps the protection
/// stateless, so it survives the loss of the sync record files.
enum BlockerNotes {

    /// Prefix of the notes line listing the origin calendar identifiers.
    private static let originsPrefix = "Origins:"

    /// Builds the notes of a blocker deriving from the given calendars.
    ///
    /// - Parameter origins: Origin calendar identifiers, oldest first.
    static func compose(origins: [String]) -> String {
        "\(CalendarService.blockerNotesTag)\n\(originsPrefix) \(origins.joined(separator: ", "))"
    }

    /// Whether the notes identify an event as a CalMirror blocker.
    static func isManaged(_ notes: String?) -> Bool {
        notes?.contains(CalendarService.blockerNotesTag) == true
    }

    /// Extracts the origin chain from an event's notes.
    ///
    /// Returns an empty array for events that are not CalMirror blockers (an
    /// `Origins:` line typed by a user is never trusted) and for blockers
    /// created before origins were recorded. Parsing is lenient on whitespace
    /// and line endings because calendar servers may rewrite the notes.
    static func origins(fromNotes notes: String?) -> [String] {
        guard let notes, isManaged(notes) else { return [] }

        let originsLine = notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(originsPrefix) }
        guard let originsLine else { return [] }

        return originsLine
            .dropFirst(originsPrefix.count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Computes the origin chain of the blocker mirroring a source event:
    /// the source event's own chain (when it is itself a blocker) extended
    /// with the calendar it is read from.
    ///
    /// - Parameters:
    ///   - sourceNotes: Notes of the source event.
    ///   - sourceCalendarIdentifier: Identifier of the rule's source calendar.
    static func originsForBlocker(sourceNotes: String?, sourceCalendarIdentifier: String) -> [String] {
        let inherited = origins(fromNotes: sourceNotes)
        return inherited.contains(sourceCalendarIdentifier)
            ? inherited
            : inherited + [sourceCalendarIdentifier]
    }

    /// Whether mirroring a source event into the target calendar would send a
    /// blocker back to a calendar it derives from.
    ///
    /// - Parameters:
    ///   - sourceNotes: Notes of the source event.
    ///   - targetCalendarIdentifier: Identifier of the rule's target calendar.
    static func wouldLoop(sourceNotes: String?, targetCalendarIdentifier: String) -> Bool {
        origins(fromNotes: sourceNotes).contains(targetCalendarIdentifier)
    }
}
