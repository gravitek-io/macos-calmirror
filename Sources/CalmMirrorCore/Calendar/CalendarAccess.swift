import Foundation

/// Small value description of a calendar needed by the sync engine.
struct CalendarDescriptor: Sendable {
    let identifier: String
    let title: String
    let allowsContentModifications: Bool
}

/// Event fields consumed by reconciliation. The handle is opaque to the engine
/// and is resolved to an EventKit object only by the production adapter.
struct CalendarEventSnapshot: Sendable {
    let handle: String
    let identifier: String
    let externalIdentifier: String
    let calendarIdentifier: String
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
    let isCanceled: Bool
}

enum BlockerResolution {
    case found(CalendarEventSnapshot)
    case missing
    case foreign
    case untagged
    case ambiguous
}

enum CalendarAccessError: Error, LocalizedError {
    case calendarUnavailable(String)
    case eventUnavailable
    var errorDescription: String? {
        switch self {
        case .calendarUnavailable(let id): return "Calendar is no longer available (identifier: \(id))."
        case .eventUnavailable: return "The EventKit event handle is no longer available."
        }
    }
}

/// Execution boundary shared by EventKit and deterministic staged-state fakes.
protocol CalendarAccess {
    func calendarDescriptor(withIdentifier id: String) -> CalendarDescriptor?
    func fetchEvents(in calendar: CalendarDescriptor, from: Date, to: Date,
                     retainHandles: Bool) throws -> [CalendarEventSnapshot]
    func resolveBlocker(for record: SyncRecord, in target: CalendarDescriptor) throws -> BlockerResolution
    func createBlockerEvent(in calendar: CalendarDescriptor, title: String, startDate: Date,
                            endDate: Date, isAllDay: Bool, notes: String, commit: Bool) throws -> CalendarEventSnapshot
    func updateBlockerEvent(_ event: CalendarEventSnapshot, title: String, startDate: Date,
                            endDate: Date, isAllDay: Bool, notes: String, commit: Bool) throws
    func deleteEvent(_ event: CalendarEventSnapshot, commit: Bool) throws
    func commitChanges() throws
    func discardPendingChanges()
    func releaseEventHandles()
}
