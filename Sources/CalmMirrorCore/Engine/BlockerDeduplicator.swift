import Foundation

/// Identity of a blocker as the user sees it in a calendar: same title and
/// same time means "the same event", whatever its EventKit identifier.
///
/// Dates are compared at one-second precision because EventKit may truncate
/// sub-second components when persisting an event.
struct BlockerKey: Hashable {
    let title: String
    let startSeconds: Int
    let endSeconds: Int
    let isAllDay: Bool

    init(title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        self.title = title
        self.startSeconds = Int(startDate.timeIntervalSince1970)
        self.endSeconds = Int(endDate.timeIntervalSince1970)
        self.isAllDay = isAllDay
    }
}

/// Guards against mirroring the same blocker several times into one calendar.
///
/// Source calendars can legitimately hold several events with an identical
/// title and time (e.g. an organizer re-sending a recurring series, or an
/// Exchange account exposing the series twice). Each has its own event
/// identifier, so without this guard each would get its own blocker.
enum BlockerDeduplicator {

    /// Keeps a single item per content hash, preserving the input order.
    ///
    /// The content hash (see ``ContentHasher``) covers exactly what defines a
    /// blocker: title, start, end and all-day flag. Among items sharing a hash,
    /// the first one that is already mirrored is preferred so its existing
    /// blocker is reused; otherwise the first item wins. Dropped items that
    /// were mirrored lose their match in the diff, so their now-redundant
    /// blockers are removed as orphans — this self-heals existing duplicates.
    ///
    /// - Parameters:
    ///   - items: Candidate source events, in fetch order.
    ///   - contentHash: Returns the blocker content hash for an item.
    ///   - isAlreadyMirrored: Returns `true` when a sync record exists for the item.
    /// - Returns: The items to mirror, at most one per content hash.
    static func collapseDuplicates<Item>(
        _ items: [Item],
        contentHash: (Item) -> String,
        isAlreadyMirrored: (Item) -> Bool
    ) -> [Item] {
        // Index of the representative chosen for each hash.
        var representative: [String: Int] = [:]
        var representativeIsMirrored: Set<String> = []

        for (index, item) in items.enumerated() {
            let hash = contentHash(item)
            let mirrored = isAlreadyMirrored(item)

            if representative[hash] == nil || (mirrored && !representativeIsMirrored.contains(hash)) {
                representative[hash] = index
            }
            if mirrored {
                representativeIsMirrored.insert(hash)
            }
        }

        let keptIndexes = Set(representative.values)
        return items.enumerated()
            .filter { keptIndexes.contains($0.offset) }
            .map(\.element)
    }
}
