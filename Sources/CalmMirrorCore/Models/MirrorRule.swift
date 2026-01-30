import Foundation

/// A user-configured mirror rule that defines how events from a source calendar
/// are replicated as blocker entries in a dedicated target calendar.
///
/// Persisted in UserDefaults under the shared suite `com.gravitek.calmirror`.
/// The `targetCalendarIdentifier` points to a dedicated CalMirror calendar
/// created specifically for this rule within the user's chosen calendar account.
public struct MirrorRule: Codable, Identifiable, Hashable, Sendable {

    // MARK: - Constants

    /// UserDefaults key used to persist the array of mirror rules.
    public static let userDefaultsKey = "mirrorRules"

    // MARK: - Validation

    /// Errors that can occur when validating a mirror rule's configuration.
    public enum ValidationError: Error, LocalizedError {
        /// Source and target calendars must be different to avoid feedback loops.
        case selfMirroring
        /// The sync window must be between 1 and 120 days inclusive.
        case windowOutOfRange
        /// The blocker label cannot be empty or whitespace-only.
        case emptyLabel
        /// The rule title cannot be empty or whitespace-only.
        case emptyTitle

        public var errorDescription: String? {
            switch self {
            case .selfMirroring:
                return "Source and target calendars must be different."
            case .windowOutOfRange:
                return "Sync window must be between 1 and 120 days."
            case .emptyLabel:
                return "Blocker label must not be empty."
            case .emptyTitle:
                return "Rule title must not be empty."
            }
        }
    }

    // MARK: - Properties

    /// Unique identifier for this rule.
    public let id: UUID

    /// Human-readable name identifying this rule in the UI and CLI.
    /// Distinct from `blockerLabel`, which is the text used for blocker events.
    public var title: String

    /// EKCalendar.calendarIdentifier of the source calendar to read events from.
    /// The sync engine treats this calendar as strictly read-only.
    public let sourceCalendarIdentifier: String

    /// EKCalendar.calendarIdentifier of the dedicated CalMirror calendar
    /// where blocker events are created.
    public let targetCalendarIdentifier: String

    /// Number of days forward from today defining the sliding sync window.
    /// Events within [today, today + windowDays] are considered for mirroring.
    /// Valid range: 1...120.
    public var windowDays: Int

    /// Label text used as the title for every blocker event created by this rule.
    /// Example: "[Client] Busy". No source event data is included.
    public var blockerLabel: String

    /// Whether this rule is enabled for automatic sync execution.
    /// Disabled rules are skipped during sync cycles but retain their configuration.
    public var isEnabled: Bool

    /// Timestamp when this rule was first created.
    public let createdAt: Date

    /// Timestamp of the most recent modification to this rule's configuration.
    public var updatedAt: Date

    // MARK: - Initializers

    /// Creates a new mirror rule with all properties specified explicitly.
    public init(
        id: UUID,
        title: String,
        sourceCalendarIdentifier: String,
        targetCalendarIdentifier: String,
        windowDays: Int,
        blockerLabel: String,
        isEnabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.sourceCalendarIdentifier = sourceCalendarIdentifier
        self.targetCalendarIdentifier = targetCalendarIdentifier
        self.windowDays = windowDays
        self.blockerLabel = blockerLabel
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience initializer that creates a new rule with sensible defaults.
    ///
    /// Assigns a fresh UUID, enables the rule, and sets both timestamps to now.
    /// - Parameters:
    ///   - title: Human-readable name identifying this rule.
    ///   - sourceCalendarIdentifier: The calendar to read events from.
    ///   - targetCalendarIdentifier: The dedicated CalMirror calendar for blockers.
    ///   - windowDays: Number of days forward to sync (1...120).
    ///   - blockerLabel: Text label for created blocker events.
    public init(
        title: String,
        sourceCalendarIdentifier: String,
        targetCalendarIdentifier: String,
        windowDays: Int,
        blockerLabel: String
    ) {
        let now = Date()
        self.init(
            id: UUID(),
            title: title,
            sourceCalendarIdentifier: sourceCalendarIdentifier,
            targetCalendarIdentifier: targetCalendarIdentifier,
            windowDays: windowDays,
            blockerLabel: blockerLabel,
            isEnabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Codable (Backward Compatibility)

    /// Coding keys for JSON serialization.
    ///
    /// The `title` key is optional during decoding to support existing rules
    /// persisted before the `title` property was introduced. When absent,
    /// `title` defaults to `blockerLabel` so legacy rules remain usable.
    private enum CodingKeys: String, CodingKey {
        case id, title, sourceCalendarIdentifier, targetCalendarIdentifier
        case windowDays, blockerLabel, isEnabled, createdAt, updatedAt
    }

    /// Decodes a `MirrorRule` from JSON, falling back to `blockerLabel` for
    /// the `title` field when it is absent (backward compatibility).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceCalendarIdentifier = try container.decode(String.self, forKey: .sourceCalendarIdentifier)
        targetCalendarIdentifier = try container.decode(String.self, forKey: .targetCalendarIdentifier)
        windowDays = try container.decode(Int.self, forKey: .windowDays)
        blockerLabel = try container.decode(String.self, forKey: .blockerLabel)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Fall back to blockerLabel when title is missing (pre-existing rules).
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? blockerLabel
    }

    // MARK: - Validation

    /// Validates the proposed configuration for a mirror rule.
    ///
    /// Returns `nil` when all parameters are valid. Returns the first
    /// encountered validation error otherwise.
    ///
    /// - Parameters:
    ///   - title: Human-readable rule name (must not be empty/whitespace).
    ///   - sourceCalendarIdentifier: The calendar to read events from.
    ///   - targetCalendarIdentifier: The dedicated CalMirror calendar for blockers.
    ///   - windowDays: Number of days forward to sync (must be 1...120).
    ///   - blockerLabel: Text label for blocker events (must not be empty/whitespace).
    /// - Returns: A `ValidationError` if the configuration is invalid, or `nil` if valid.
    public static func validate(
        title: String,
        sourceCalendarIdentifier: String,
        targetCalendarIdentifier: String,
        windowDays: Int,
        blockerLabel: String
    ) -> ValidationError? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyTitle
        }
        if sourceCalendarIdentifier == targetCalendarIdentifier {
            return .selfMirroring
        }
        if !(1...120).contains(windowDays) {
            return .windowOutOfRange
        }
        if blockerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyLabel
        }
        return nil
    }
}
