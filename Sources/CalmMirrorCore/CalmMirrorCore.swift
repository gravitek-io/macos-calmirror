/// CalmMirrorCore provides the shared models, sync engine, storage, and calendar
/// access layer used by both the SwiftUI menu bar app and the CLI tool.
///
/// This module contains no UI code and is the single source of truth for:
/// - Mirror rule configuration (``MirrorRule``)
/// - Source-to-blocker event mapping (``SyncRecord``)
/// - Sync execution logging (``SyncLog``)
/// - Calendar read/write operations (``CalendarService``)
/// - Sync diff algorithm (``SyncEngine``)
public enum CalmMirrorCore {
    /// The current version of the CalmMirrorCore library.
    public static let version = "1.1.0"
}
