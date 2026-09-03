// SyncCoordinator.swift
// CalMirror — macOS Application
//
// Drives the "Sync Now" feature: asks launchd to run the background sync
// agent immediately, waits for it to finish and exposes the outcome to the
// views. The app never runs a sync itself; the agent remains the single
// process writing to the calendars.
//
// Requirements: macOS 26+, Swift 6.2+

import CalmMirrorCore
import Foundation
import Observation

/// Triggers on-demand runs of the launchd sync agent and tracks their outcome.
///
/// A single instance is created by the root view and shared through the
/// SwiftUI environment. Views call ``requestSync()`` (toolbar button, rule
/// created or edited, rule re-enabled) and observe ``isSyncing``,
/// ``lastError``, ``lastSyncDate`` and ``latestLogByRule`` to render status.
///
/// ## How a run is observed
/// `launchctl kickstart` returns immediately, so completion is detected
/// indirectly: the coordinator remembers the trigger time, polls the agent's
/// run state through `LaunchdManager.status()` and reads the sync logs the
/// agent appends. A run is considered finished once the agent is no longer
/// running, or once new logs appeared for a run too short to be observed.
///
/// ## Coalescing
/// If a sync is requested while one is in progress (for example a rule is
/// created then edited right away), the request is remembered and a second
/// run is started when the first one completes. The second run guarantees
/// the latest rule changes are picked up, since the running agent may have
/// loaded the rules before the change.
@MainActor
@Observable
final class SyncCoordinator {

    // MARK: - Tuning

    /// Interval between two polls of the agent state and the log file.
    private static let pollInterval: Duration = .seconds(1)

    /// Maximum time to wait for the agent before reporting a failure.
    /// A sync of a few rules takes seconds; a minute leaves room for a
    /// slow first EventKit access without leaving the UI stuck for long.
    private static let timeout: TimeInterval = 60

    // MARK: - Observable State

    /// Whether a run triggered by the app is in progress.
    private(set) var isSyncing = false

    /// A human-readable description of the last failure, or `nil` when the
    /// last run succeeded. Cleared when a new run starts.
    private(set) var lastError: String?

    /// Timestamp of the most recent sync log on disk, whatever triggered it
    /// (the scheduled agent or the app). `nil` when no sync ever ran.
    private(set) var lastSyncDate: Date?

    /// The most recent sync log of every rule, keyed by rule identifier.
    private(set) var latestLogByRule: [UUID: SyncLog] = [:]

    // MARK: - Private State

    /// Set when ``requestSync()`` is called during a run; consumed by the run
    /// loop to start one more run after the current one completes.
    private var rerunRequested = false

    // MARK: - Public API

    /// Reloads ``lastSyncDate`` and ``latestLogByRule`` from the log store.
    ///
    /// Called on appear and after every run so the views reflect syncs made
    /// by the scheduled agent as well as the ones triggered from the app.
    func refresh() {
        guard let store = try? SyncLogStore() else {
            lastSyncDate = nil
            latestLogByRule = [:]
            return
        }
        let latest = store.latestLogByRule()
        latestLogByRule = latest
        lastSyncDate = latest.values.map(\.timestamp).max()
    }

    /// Asks the agent to sync now.
    ///
    /// Returns immediately. If a run is already in progress the request is
    /// coalesced into a follow-up run (see the type documentation).
    func requestSync() {
        if isSyncing {
            rerunRequested = true
            return
        }
        Task { await run() }
    }

    // MARK: - Run Loop

    /// Executes one or more runs until no follow-up request is pending.
    private func run() async {
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // A run that records nothing may be one that was already in progress
        // when the kickstart arrived (launchd ignores the request and the
        // rules loaded by that run predate the change). One retry covers it.
        var retriedEmptyRun = false

        repeat {
            rerunRequested = false
            let triggeredAt = Date()

            do {
                try await Self.kickstartAgent()
            } catch {
                lastError = Self.describeKickstartFailure(error)
                return
            }

            let outcome = await waitForCompletion(since: triggeredAt)
            refresh()

            switch outcome {
            case .completed(let logs) where logs.isEmpty && !retriedEmptyRun:
                retriedEmptyRun = true
                rerunRequested = true
            case .completed(let logs) where logs.isEmpty:
                // The agent ran twice and recorded nothing. Typical causes: no
                // enabled rule, or the CLI binary was never granted calendar
                // access (the agent then exits before syncing).
                lastError = "The sync agent ran but recorded no result. "
                    + "Check `calmirror status` and the calendar access of the CLI."
            case .completed:
                lastError = nil
            case .timedOut:
                lastError = "The sync agent did not finish within \(Int(Self.timeout)) seconds. "
                    + "Check `calmirror status` and /tmp/calmirror.stderr.log."
            }
        } while rerunRequested
    }

    /// Result of waiting for a triggered run.
    private enum Outcome {
        /// The agent finished; `logs` are the entries it appended.
        case completed(logs: [SyncLog])
        /// The agent was still running (or never observed) when the timeout expired.
        case timedOut
    }

    /// Polls the agent state and the log store until the triggered run ends.
    ///
    /// Two completion signals are accepted:
    /// - the agent was seen running and is no longer running;
    /// - new logs exist and the agent is not running, which covers a run that
    ///   completed between two polls.
    ///
    /// - Parameter triggeredAt: The moment the kickstart was issued; only logs
    ///   recorded from then on belong to this run.
    /// - Returns: The outcome once the run ends or the timeout expires.
    private func waitForCompletion(since triggeredAt: Date) async -> Outcome {
        var sawRunning = false

        while Date().timeIntervalSince(triggeredAt) < Self.timeout {
            try? await Task.sleep(for: Self.pollInterval)

            let running = await Self.isAgentRunning()
            let logs = await Self.loadLogs(since: triggeredAt)

            if running {
                sawRunning = true
                continue
            }

            if sawRunning || !logs.isEmpty {
                return .completed(logs: logs)
            }
        }

        return .timedOut
    }

    // MARK: - Background Helpers

    /// Runs `launchctl kickstart` off the main actor; the call blocks on the
    /// subprocess for a few milliseconds.
    private static func kickstartAgent() async throws {
        try await Task.detached(priority: .userInitiated) {
            try LaunchdManager().kickstart()
        }.value
    }

    /// Queries launchd off the main actor for the agent's run state.
    private static func isAgentRunning() async -> Bool {
        await Task.detached(priority: .utility) {
            LaunchdManager().status().running
        }.value
    }

    /// Reads the logs appended since the trigger, off the main actor.
    private static func loadLogs(since date: Date) async -> [SyncLog] {
        await Task.detached(priority: .utility) {
            (try? SyncLogStore())?.loadLogs(since: date) ?? []
        }.value
    }

    /// Turns a kickstart error into guidance the user can act on.
    private static func describeKickstartFailure(_ error: Error) -> String {
        if case LaunchdManagerError.notInstalled = error {
            return "The background sync agent is not installed. "
                + "Run the installer with --cli or `calmirror agent install`."
        }
        return "Could not start the sync agent: \(error.localizedDescription)"
    }
}
