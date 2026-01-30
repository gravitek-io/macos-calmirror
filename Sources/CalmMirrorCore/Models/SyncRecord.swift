import Foundation

/// Maps a source event occurrence to the blocker event created for it.
///
/// Persisted in a JSON file specific to each MirrorRule.
/// Used by the sync engine to detect changes (via `sourceContentHash`),
/// update blocker timing, and clean up orphaned blockers.
public struct SyncRecord: Codable, Identifiable, Sendable {
    /// Derived identifier combining source event identifier and start date for uniqueness.
    /// Format: "{sourceEventIdentifier}_{sourceStartDate.timeIntervalSince1970}"
    public var id: String {
        "\(sourceEventIdentifier)_\(Int(sourceStartDate.timeIntervalSince1970))"
    }

    // MARK: - Source Event

    /// EKEvent.eventIdentifier of the source event.
    /// Primary lookup key. Stable within a single device.
    public let sourceEventIdentifier: String

    /// EKEvent.calendarItemExternalIdentifier of the source event.
    /// Used as fallback when eventIdentifier changes (e.g., after Exchange sync).
    public let sourceExternalIdentifier: String

    /// Start date of the source event occurrence.
    public let sourceStartDate: Date

    /// End date of the source event occurrence.
    public let sourceEndDate: Date

    /// Whether the source event is an all-day event.
    public let sourceIsAllDay: Bool

    /// Hash of (startDate + endDate + isAllDay) for efficient change detection.
    public let sourceContentHash: String

    // MARK: - Blocker Event

    /// EKEvent.eventIdentifier of the blocker event created in the target calendar.
    public let blockerEventIdentifier: String

    /// EKEvent.calendarItemExternalIdentifier of the blocker event.
    public let blockerExternalIdentifier: String

    // MARK: - Metadata

    /// Timestamp of the last successful sync that created or updated this record.
    public let lastSyncedAt: Date

    // MARK: - Initializer

    /// Creates a new SyncRecord with all required fields.
    ///
    /// - Parameters:
    ///   - sourceEventIdentifier: EKEvent.eventIdentifier of the source event.
    ///   - sourceExternalIdentifier: EKEvent.calendarItemExternalIdentifier of the source event.
    ///   - sourceStartDate: Start date of the source event occurrence.
    ///   - sourceEndDate: End date of the source event occurrence.
    ///   - sourceIsAllDay: Whether the source event is an all-day event.
    ///   - sourceContentHash: Hash of timing fields for change detection.
    ///   - blockerEventIdentifier: EKEvent.eventIdentifier of the blocker event.
    ///   - blockerExternalIdentifier: EKEvent.calendarItemExternalIdentifier of the blocker event.
    ///   - lastSyncedAt: Timestamp of the last successful sync.
    public init(
        sourceEventIdentifier: String,
        sourceExternalIdentifier: String,
        sourceStartDate: Date,
        sourceEndDate: Date,
        sourceIsAllDay: Bool,
        sourceContentHash: String,
        blockerEventIdentifier: String,
        blockerExternalIdentifier: String,
        lastSyncedAt: Date
    ) {
        self.sourceEventIdentifier = sourceEventIdentifier
        self.sourceExternalIdentifier = sourceExternalIdentifier
        self.sourceStartDate = sourceStartDate
        self.sourceEndDate = sourceEndDate
        self.sourceIsAllDay = sourceIsAllDay
        self.sourceContentHash = sourceContentHash
        self.blockerEventIdentifier = blockerEventIdentifier
        self.blockerExternalIdentifier = blockerExternalIdentifier
        self.lastSyncedAt = lastSyncedAt
    }
}
