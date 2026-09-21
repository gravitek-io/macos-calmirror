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

    /// Keeps a single item per blocker key, preserving the input order.
    ///
    /// The ``BlockerKey`` covers what makes two blockers look identical in a
    /// calendar: title, start, end and all-day flag. Among items sharing a key,
    /// the first one that is already mirrored is preferred so its existing
    /// blocker is reused; otherwise the first item wins. Dropped items that
    /// were mirrored lose their match in the diff, so their now-redundant
    /// blockers are removed as orphans — this self-heals existing duplicates.
    ///
    /// - Parameters:
    ///   - items: Candidate source events, in fetch order.
    ///   - blockerKey: Returns the key of the blocker an item would produce.
    ///   - isAlreadyMirrored: Returns `true` when a sync record exists for the item.
    /// - Returns: The items to mirror, at most one per blocker key.
    static func collapseDuplicates<Item, Key: Hashable>(
        _ items: [Item],
        blockerKey: (Item) -> Key,
        isAlreadyMirrored: (Item) -> Bool
    ) -> [Item] {
        // Index of the representative chosen for each key.
        var representative: [Key: Int] = [:]
        var representativeIsMirrored: Set<Key> = []

        for (index, item) in items.enumerated() {
            let key = blockerKey(item)
            let mirrored = isAlreadyMirrored(item)

            if representative[key] == nil || (mirrored && !representativeIsMirrored.contains(key)) {
                representative[key] = index
            }
            if mirrored {
                representativeIsMirrored.insert(key)
            }
        }

        let keptIndexes = Set(representative.values)
        return items.enumerated()
            .filter { keptIndexes.contains($0.offset) }
            .map(\.element)
    }
}
