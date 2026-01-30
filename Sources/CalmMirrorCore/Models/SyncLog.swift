import Foundation

// MARK: - SyncLog

/// Records the outcome of a single sync execution for one mirror rule.
///
/// Each `SyncLog` captures every blocker event that was added, removed, or updated
/// during a sync pass, along with any errors that occurred.
///
/// Persisted in a shared JSON log file with rolling retention (last 30 days).
/// Displayed in the UI logs view for user troubleshooting.
public struct SyncLog: Codable, Identifiable, Sendable {

    /// Unique identifier for this log entry.
    public let id: UUID

    /// Identifier of the mirror rule that triggered this sync.
    public let ruleId: UUID

    /// Date and time when the sync execution started.
    public let timestamp: Date

    /// Wall-clock duration of the sync execution, in seconds.
    public let durationSeconds: Double

    /// Blocker events that were created during this sync.
    public let added: [BlockerChange]

    /// Blocker events that were deleted during this sync.
    public let removed: [BlockerChange]

    /// Blocker events that were modified during this sync.
    public let updated: [BlockerChange]

    /// Errors encountered during this sync execution.
    public let errors: [SyncError]

    /// Number of blocker events added.
    public var addedCount: Int { added.count }

    /// Number of blocker events removed.
    public var removedCount: Int { removed.count }

    /// Number of blocker events updated.
    public var updatedCount: Int { updated.count }

    /// Whether the sync completed without any errors.
    public var isSuccess: Bool { errors.isEmpty }

    /// Creates a new sync log entry.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this log entry. Defaults to a new UUID.
    ///   - ruleId: Identifier of the mirror rule that triggered this sync.
    ///   - timestamp: Date and time when the sync execution started.
    ///   - durationSeconds: Wall-clock duration of the sync execution, in seconds.
    ///   - added: Blocker events that were created during this sync.
    ///   - removed: Blocker events that were deleted during this sync.
    ///   - updated: Blocker events that were modified during this sync.
    ///   - errors: Errors encountered during this sync execution.
    public init(
        id: UUID = UUID(),
        ruleId: UUID,
        timestamp: Date,
        durationSeconds: Double,
        added: [BlockerChange],
        removed: [BlockerChange],
        updated: [BlockerChange],
        errors: [SyncError]
    ) {
        self.id = id
        self.ruleId = ruleId
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.added = added
        self.removed = removed
        self.updated = updated
        self.errors = errors
    }
}

// MARK: - BlockerChange

/// Describes a single blocker event change (creation, deletion, or update).
///
/// Captures the time boundaries and all-day flag of the blocker calendar event
/// that was affected during a sync pass.
public struct BlockerChange: Codable, Sendable {

    /// Start date (and time, unless `isAllDay`) of the blocker event.
    public let startDate: Date

    /// End date (and time, unless `isAllDay`) of the blocker event.
    public let endDate: Date

    /// Whether the blocker event spans entire calendar days.
    public let isAllDay: Bool

    /// Creates a new blocker change record.
    ///
    /// - Parameters:
    ///   - startDate: Start date of the blocker event.
    ///   - endDate: End date of the blocker event.
    ///   - isAllDay: Whether the blocker event spans entire calendar days.
    public init(startDate: Date, endDate: Date, isAllDay: Bool) {
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }
}

// MARK: - SyncError

/// Describes an error that occurred during sync execution.
///
/// Each error carries a categorised ``ErrorCode`` for programmatic handling
/// and a human-readable ``message`` for display in the logs view.
public struct SyncError: Codable, Sendable {

    /// Categorised error code identifying the failure type.
    public let code: ErrorCode

    /// Human-readable description of the error for troubleshooting.
    public let message: String

    /// Known error categories encountered during sync.
    public enum ErrorCode: String, Codable, Sendable {
        /// The specified source or destination calendar could not be found.
        case calendarNotFound
        /// The destination calendar does not allow write operations.
        case calendarReadOnly
        /// The app lacks permission to access the calendar store.
        case accessDenied
        /// An internal EventKit framework error occurred.
        case eventKitInternal
        /// A specific blocker event operation (add, remove, or update) failed.
        case blockerOperationFailed
        /// An unexpected or unclassified error.
        case unknown
    }

    /// Creates a new sync error.
    ///
    /// - Parameters:
    ///   - code: Categorised error code identifying the failure type.
    ///   - message: Human-readable description of the error.
    public init(code: ErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
