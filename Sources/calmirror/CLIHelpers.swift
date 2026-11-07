import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

typealias LaunchdAgentStatus = AgentStatus

// MARK: - Helpers

/// Writes a message to standard error, followed by a newline.
///
/// All error, warning, and diagnostic output is directed to stderr so that
/// structured stdout output remains clean for piping and JSON consumers.
///
/// - Parameter message: The text to write to stderr.
func writeToStderr(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(Data((message + "\n").utf8))
}

/// Short identifier for human-readable output (first 8 characters of a UUID or calendar id).
///
/// - Parameter identifier: The full identifier string.
/// - Returns: The first 8 characters, or the full string if shorter.
func shortID(_ identifier: String) -> String {
    String(identifier.prefix(8))
}

/// Ensures the app has full calendar access, requesting it if needed.
///
/// When the authorization status is `.notDetermined`, this function
/// triggers the system permission prompt using a semaphore to bridge
/// the async `requestFullAccessToEvents()` API into synchronous context.
/// If access is denied or the request fails, prints an error to stderr
/// and terminates with exit code 4.
func requireCalendarAccess() {
    let status = CalendarService.shared.checkAuthorizationStatus()

    switch status {
    case .fullAccess:
        return

    case .notDetermined:
        // Bridge the async permission request into synchronous CLI context.
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false

        Task {
            do {
                granted = try await CalendarService.shared.requestAccess()
            } catch {
                // Request failed; granted stays false.
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard granted else {
            writeToStderr(
                "error: calendar access denied. "
                + "Grant Full Access in System Settings > Privacy & Security > Calendars."
            )
            Darwin.exit(4)
        }

    default:
        writeToStderr(
            "error: calendar access denied. "
            + "Grant Full Access in System Settings > Privacy & Security > Calendars."
        )
        Darwin.exit(4)
    }
}

// MARK: - Signal Handling

/// Flag indicating that a graceful termination has been requested.
///
/// Set to `true` by the SIGTERM and SIGINT signal handlers installed
/// in the Sync command. The sync loop checks this flag between rules
/// and stops processing additional rules when set, allowing the
/// currently executing rule to finish its commit batch before exiting.
///
/// This ensures launchd stop/restart does not leave orphaned or
/// incomplete sync state. Completed rules retain their full state;
/// only un-started rules are skipped.
var shouldTerminate = false
