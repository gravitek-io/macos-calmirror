import EventKit
import Foundation

/// Wraps the EventKit EKEventStore singleton, providing calendar enumeration,
/// event fetching, and blocker event CRUD operations.
///
/// This service is the sole point of contact with the EventKit framework.
/// It enforces the singleton pattern for EKEventStore to prevent
/// calaccessd connection exhaustion on macOS 14+.
///
/// ## Usage
/// ```swift
/// let granted = try await CalendarService.shared.requestAccess()
/// let calendars = CalendarService.shared.calendarsByAccount()
/// ```
///
/// ## Thread Safety
/// EKEventStore is not Sendable. The CLI uses serial execution; the GUI
/// confines access to `@MainActor`. Do not share across unstructured
/// concurrent contexts.
public final class CalendarService {

    // MARK: - Singleton

    /// Shared instance -- EKEventStore must be a singleton to avoid
    /// exhausting calaccessd connections on macOS 14+.
    public static let shared = CalendarService()

    // MARK: - Constants

    /// Tag placed in the notes field of every managed blocker event.
    /// Used as a safety-net identifier when the JSON mapping is unavailable.
    public static let blockerNotesTag = "Managed by CalMirror"

    // MARK: - Properties

    /// The underlying EventKit store. Only one instance must exist per process.
    private let eventStore: EKEventStore

    // MARK: - Initializers

    /// Creates the singleton calendar service with a private EKEventStore.
    private init() {
        self.eventStore = EKEventStore()
    }

    /// Creates a calendar service backed by the given event store.
    ///
    /// Intended **only** for unit tests that inject a mock or pre-configured store.
    /// Production code must use ``shared``.
    ///
    /// - Parameter eventStore: The event store instance to use.
    internal init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    // MARK: - Authorization

    /// Requests full read/write access to the user's calendar events.
    ///
    /// Calls the macOS 14+ `requestFullAccessToEvents()` API. The system
    /// prompt is shown only on the first invocation; subsequent calls return
    /// the persisted authorization decision immediately.
    ///
    /// - Returns: `true` if access was granted, `false` otherwise.
    /// - Throws: An error if the authorization request itself fails.
    @available(macOS 14.0, *)
    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    /// Returns the current calendar-event authorization status without
    /// prompting the user.
    ///
    /// Use this to check permissions before starting a sync cycle so the
    /// engine can surface a clear error rather than silently failing.
    ///
    /// - Returns: The authorization status for event-type data.
    public func checkAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Calendar Enumeration

    /// Returns all calendars of type `.event` known to the event store.
    ///
    /// This includes calendars from every configured account (iCloud,
    /// Google, Exchange, local, etc.). The list is not filtered by
    /// writability; use ``calendarsByAccount()`` if you need that annotation.
    ///
    /// - Returns: An array of all event calendars.
    public func allCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    /// Groups event calendars by their source (account), annotating each
    /// calendar with its writability status.
    ///
    /// Each entry in the returned array represents one calendar account
    /// (e.g. "iCloud", "Google", "Exchange"). Within each account, calendars
    /// are listed with a `writable` flag derived from
    /// `allowsContentModifications`.
    ///
    /// The accounts are sorted alphabetically by name; calendars within
    /// each account are sorted alphabetically by title.
    ///
    /// - Returns: An array of tuples pairing account names with their calendars.
    public func calendarsByAccount() -> [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])] {
        let calendars = eventStore.calendars(for: .event)

        // Group calendars by their EKSource title (account name).
        let grouped = Dictionary(grouping: calendars) { calendar in
            calendar.source?.title ?? "Unknown"
        }

        // Sort accounts alphabetically, then sort calendars within each account.
        return grouped
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (account, calendars) in
                let annotated = calendars
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    .map { calendar in
                        (calendar: calendar, writable: calendar.allowsContentModifications)
                    }
                return (account: account, calendars: annotated)
            }
    }

    /// Looks up a single calendar by its persistent identifier.
    ///
    /// - Parameter id: The `calendarIdentifier` string returned by EventKit.
    /// - Returns: The matching calendar, or `nil` if it no longer exists
    ///   (e.g. the account was removed or the calendar was deleted).
    public func calendar(withIdentifier id: String) -> EKCalendar? {
        eventStore.calendar(withIdentifier: id)
    }

    // MARK: - Event Fetching

    /// Fetches all events in the given calendar within the specified date range.
    ///
    /// Recurring events are automatically expanded into individual occurrences
    /// by EventKit's `predicateForEvents` implementation. The maximum supported
    /// range is four years, which is well within the typical 7-120 day sync window.
    ///
    /// - Parameters:
    ///   - calendar: The calendar to fetch events from.
    ///   - startDate: The inclusive start of the date range.
    ///   - endDate: The exclusive end of the date range.
    /// - Returns: An array of events occurring within the range.
    public func fetchEvents(
        in calendar: EKCalendar,
        from startDate: Date,
        to endDate: Date
    ) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate)
    }

    // MARK: - Blocker CRUD

    /// Creates a new blocker event with only the minimal required fields.
    ///
    /// The event is configured with:
    /// - The specified calendar, title, dates, and all-day flag
    /// - Availability set to `.busy`
    /// - Notes set to ``blockerNotesTag``
    ///
    /// All other fields are explicitly left `nil` or empty to avoid leaking
    /// source event data: location, structuredLocation, URL, alarms, and
    /// recurrenceRules are never set. Attendees and organizer are read-only
    /// properties on `EKEvent` and are not populated for new events.
    ///
    /// - Parameters:
    ///   - calendar: The target calendar where the blocker is created.
    ///   - title: The blocker label (e.g. "[Client] Busy").
    ///   - startDate: The blocker's start time.
    ///   - endDate: The blocker's end time.
    ///   - isAllDay: Whether the blocker spans the entire day.
    ///   - commit: If `true`, the change is committed immediately. Pass `false`
    ///     when batching multiple operations and call ``commitChanges()`` afterward.
    /// - Returns: The newly created and saved `EKEvent`.
    /// - Throws: An `EKError` if the save operation fails.
    @discardableResult
    public func createBlockerEvent(
        in calendar: EKCalendar,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        commit: Bool
    ) throws -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.availability = .busy
        event.notes = Self.blockerNotesTag

        // Explicitly ensure no extraneous data is attached.
        event.location = nil
        event.structuredLocation = nil
        event.url = nil
        event.alarms = nil
        event.recurrenceRules = nil

        try eventStore.save(event, span: .thisEvent, commit: commit)
        return event
    }

    /// Updates the time properties of an existing blocker event.
    ///
    /// Only `startDate`, `endDate`, and `isAllDay` are modified. All other
    /// fields remain unchanged to preserve the event's identity and avoid
    /// accidentally overwriting user edits to non-managed fields.
    ///
    /// - Parameters:
    ///   - event: The blocker event to update. Must have been previously created
    ///     by CalMirror.
    ///   - startDate: The new start time.
    ///   - endDate: The new end time.
    ///   - isAllDay: The new all-day flag.
    ///   - commit: If `true`, the change is committed immediately. Pass `false`
    ///     when batching and call ``commitChanges()`` afterward.
    /// - Throws: An `EKError` if the save operation fails.
    public func updateBlockerEvent(
        _ event: EKEvent,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        commit: Bool
    ) throws {
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay

        try eventStore.save(event, span: .thisEvent, commit: commit)
    }

    /// Deletes an event from its calendar.
    ///
    /// - Parameters:
    ///   - event: The event to remove.
    ///   - commit: If `true`, the change is committed immediately. Pass `false`
    ///     when batching and call ``commitChanges()`` afterward.
    /// - Throws: An `EKError` if the removal fails.
    public func deleteEvent(_ event: EKEvent, commit: Bool) throws {
        try eventStore.remove(event, span: .thisEvent, commit: commit)
    }

    /// Commits all pending (uncommitted) changes to the event store.
    ///
    /// Call this after a batch of `save(commit: false)` and `remove(commit: false)`
    /// operations. A single commit produces one `EKEventStoreChangedNotification`
    /// regardless of how many events were modified.
    ///
    /// - Throws: An `EKError` if the commit fails.
    public func commitChanges() throws {
        try eventStore.commit()
    }

    // MARK: - Event Lookup

    /// Finds an event by its device-local identifier.
    ///
    /// This is the primary lookup path. The `eventIdentifier` is stable on a
    /// single device but may change after an Exchange sync or re-provisioning.
    /// If this returns `nil`, fall back to ``findEvents(byExternalIdentifier:)``.
    ///
    /// - Parameter id: The `eventIdentifier` of the event to find.
    /// - Returns: The matching event, or `nil` if it no longer exists.
    public func findEvent(byIdentifier id: String) -> EKEvent? {
        eventStore.event(withIdentifier: id)
    }

    /// Finds calendar items by their cross-device external identifier.
    ///
    /// This is the fallback lookup path when ``findEvent(byIdentifier:)``
    /// returns `nil`. The `calendarItemExternalIdentifier` is shared across
    /// devices via the calendar server but can change after certain Exchange
    /// sync operations.
    ///
    /// - Parameter externalId: The `calendarItemExternalIdentifier` to search for.
    /// - Returns: An array of matching calendar items (may be empty).
    public func findEvents(byExternalIdentifier externalId: String) -> [EKCalendarItem] {
        eventStore.calendarItems(withExternalIdentifier: externalId)
    }
}
