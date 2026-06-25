import CryptoKit
import Foundation

/// Computes deterministic content hashes for event time properties.
///
/// Used by the sync engine to efficiently detect changes that require updating a
/// blocker event without comparing full event objects. The hash covers the
/// time-related fields plus the blocker's derived title, so that a renamed source
/// event (which changes the title in source-name mode) is detected as a change.
public enum ContentHasher {

    /// Computes a deterministic hash representing a blocker's desired state.
    ///
    /// - Parameters:
    ///   - startDate: The event's start date.
    ///   - endDate: The event's end date.
    ///   - isAllDay: Whether the event spans the entire day.
    ///   - blockerTitle: The title the blocker should carry. Defaults to an empty
    ///     string. Including it means a source rename (which changes the derived
    ///     title in source-name mode) produces a new hash and triggers an update,
    ///     while placeholder-mode rules keep a constant title and avoid needless
    ///     updates.
    /// - Returns: A hex-encoded SHA-256 hash string.
    public static func computeContentHash(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        blockerTitle: String = ""
    ) -> String {
        var hasher = SHA256()
        let startInterval = startDate.timeIntervalSince1970
        let endInterval = endDate.timeIntervalSince1970
        hasher.update(data: withUnsafeBytes(of: startInterval) { Data($0) })
        hasher.update(data: withUnsafeBytes(of: endInterval) { Data($0) })
        hasher.update(data: withUnsafeBytes(of: isAllDay) { Data($0) })
        hasher.update(data: Data(blockerTitle.utf8))
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
