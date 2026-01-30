import CryptoKit
import Foundation

/// Computes deterministic content hashes for event time properties.
///
/// Used by the sync engine to efficiently detect changes in source events
/// without comparing full event objects. Only time-related fields are hashed
/// since those are the only properties mirrored to blocker events.
public enum ContentHasher {

    /// Computes a deterministic hash from the source event's time properties.
    ///
    /// - Parameters:
    ///   - startDate: The event's start date.
    ///   - endDate: The event's end date.
    ///   - isAllDay: Whether the event spans the entire day.
    /// - Returns: A hex-encoded SHA-256 hash string.
    public static func computeContentHash(startDate: Date, endDate: Date, isAllDay: Bool) -> String {
        var hasher = SHA256()
        let startInterval = startDate.timeIntervalSince1970
        let endInterval = endDate.timeIntervalSince1970
        hasher.update(data: withUnsafeBytes(of: startInterval) { Data($0) })
        hasher.update(data: withUnsafeBytes(of: endInterval) { Data($0) })
        hasher.update(data: withUnsafeBytes(of: isAllDay) { Data($0) })
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
