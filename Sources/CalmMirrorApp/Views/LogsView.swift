// LogsView.swift
// CalmMirror — macOS Menu Bar Application
//
// Displays a chronological list of sync execution logs with
// expand/collapse detail for each entry (T037).

import CalmMirrorCore
import SwiftUI

/// Displays a chronological list of `SyncLog` entries, most recent first.
///
/// Each row summarises a single sync execution: timestamp, success/failure icon,
/// change counts, associated rule label, and duration. Expanding a row via
/// `DisclosureGroup` reveals the individual `BlockerChange` entries and any
/// error messages recorded during that sync.
///
/// Logs are loaded from `SyncLogStore` on appear and can be manually refreshed
/// via the toolbar button.
struct LogsView: View {

    // MARK: - State

    /// The loaded sync log entries, displayed most recent first.
    @State private var logs: [SyncLog] = []

    /// All persisted mirror rules, used to resolve rule labels from IDs.
    @State private var rules: [MirrorRule] = []

    /// Whether the initial log load encountered an error.
    @State private var loadError: String?

    // MARK: - Formatters

    /// Formats log timestamps as "yyyy-MM-dd HH:mm:ss".
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Formats blocker change dates as "MMM d, HH:mm".
    private static let changeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        Group {
            if let loadError {
                errorStateView(message: loadError)
            } else if logs.isEmpty {
                emptyStateView
            } else {
                logListView
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh sync logs")
            }
        }
        .onAppear {
            refreshLogs()
        }
    }

    // MARK: - Subviews

    /// Placeholder shown when no sync logs have been recorded yet.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No sync logs yet. Run a sync to see results here.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Error state shown when the log store fails to initialise.
    ///
    /// - Parameter message: A human-readable error description.
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Failed to load logs")
                .font(.title3)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The main scrollable list of sync log entries.
    private var logListView: some View {
        List {
            ForEach(logs) { log in
                logRow(for: log)
            }
        }
    }

    /// A single expandable row displaying a sync log summary and detail.
    ///
    /// The collapsed header shows timestamp, status icon, change summary,
    /// rule label, and duration. Expanding the row reveals individual
    /// blocker changes and any error messages.
    ///
    /// - Parameter log: The sync log entry to display.
    @ViewBuilder
    private func logRow(for log: SyncLog) -> some View {
        DisclosureGroup {
            logDetailView(for: log)
        } label: {
            logSummaryRow(for: log)
        }
        .padding(.vertical, 2)
    }

    /// The collapsed summary content for a single log entry.
    ///
    /// Layout: status icon | timestamp | change summary | rule label | duration
    ///
    /// - Parameter log: The sync log entry to summarise.
    private func logSummaryRow(for log: SyncLog) -> some View {
        HStack(spacing: 10) {
            // Status icon: green checkmark for success, red X for errors
            statusIcon(for: log)

            // Timestamp
            Text(Self.timestampFormatter.string(from: log.timestamp))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)

            // Change summary: "+N added, -N removed, ~N updated"
            Text(changeSummary(for: log))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            // Rule label resolved from the rule store
            Text(ruleLabel(for: log.ruleId))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())

            // Duration
            Text(formattedDuration(log.durationSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Expanded detail view showing blocker changes and errors for a log entry.
    ///
    /// Groups changes into added, removed, and updated sections, each listing
    /// the start and end times of affected blocker events. Any errors are
    /// displayed at the bottom with their code and message.
    ///
    /// - Parameter log: The sync log entry to display in detail.
    private func logDetailView(for log: SyncLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !log.added.isEmpty {
                changeSection(title: "Added", changes: log.added, color: .green)
            }

            if !log.removed.isEmpty {
                changeSection(title: "Removed", changes: log.removed, color: .red)
            }

            if !log.updated.isEmpty {
                changeSection(title: "Updated", changes: log.updated, color: .orange)
            }

            if !log.errors.isEmpty {
                errorsSection(errors: log.errors)
            }

            // Show a message when there were no changes and no errors
            if log.added.isEmpty && log.removed.isEmpty && log.updated.isEmpty && log.errors.isEmpty {
                Text("No changes detected during this sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
    }

    /// Displays a labelled section of blocker changes (added, removed, or updated).
    ///
    /// Each change shows its start and end times. All-day events are annotated.
    ///
    /// - Parameters:
    ///   - title: The section heading (e.g., "Added", "Removed").
    ///   - changes: The blocker changes to display.
    ///   - color: The accent color for the section heading.
    private func changeSection(title: String, changes: [BlockerChange], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color.opacity(0.6))
                        .frame(width: 6, height: 6)

                    if change.isAllDay {
                        Text("All day: \(Self.changeDateFormatter.string(from: change.startDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Self.changeDateFormatter.string(from: change.startDate)) - \(Self.changeDateFormatter.string(from: change.endDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    /// Displays a section listing all errors encountered during a sync execution.
    ///
    /// Each error shows its categorised code and human-readable message.
    ///
    /// - Parameter errors: The sync errors to display.
    private func errorsSection(errors: [SyncError]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Errors")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.red)

            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.code.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)

                        Text(error.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Helpers

    /// Returns the appropriate SF Symbol for the log's success or error status.
    ///
    /// - Parameter log: The sync log entry to evaluate.
    /// - Returns: A green checkmark image for success, or a red X for errors.
    private func statusIcon(for log: SyncLog) -> some View {
        Group {
            if log.isSuccess {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .font(.title3)
    }

    /// Builds a compact summary string describing the number of changes.
    ///
    /// Format: "+N added, -N removed, ~N updated"
    ///
    /// - Parameter log: The sync log entry to summarise.
    /// - Returns: A human-readable change summary string.
    private func changeSummary(for log: SyncLog) -> String {
        "+\(log.addedCount) added, -\(log.removedCount) removed, ~\(log.updatedCount) updated"
    }

    /// Resolves the human-readable label for a rule, falling back to a default.
    ///
    /// Looks up the rule by its UUID in the preloaded rules array.
    /// Returns "Unknown Rule" if the rule has been deleted or is not found.
    ///
    /// - Parameter ruleId: The UUID of the mirror rule to look up.
    /// - Returns: The rule's blocker label, or "Unknown Rule".
    private func ruleLabel(for ruleId: UUID) -> String {
        rules.first(where: { $0.id == ruleId })?.title ?? "Unknown Rule"
    }

    /// Formats a duration in seconds into a compact display string.
    ///
    /// Durations under 1 second show one decimal place (e.g., "0.5s").
    /// Durations of 1 second or more show one decimal place (e.g., "2.3s").
    /// Durations of 60 seconds or more show minutes and seconds (e.g., "1m 30s").
    ///
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A compact formatted string.
    private func formattedDuration(_ seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
        return String(format: "%.1fs", seconds)
    }

    // MARK: - Data Loading

    /// Loads sync logs and rules from their respective stores, updating view state.
    ///
    /// Logs are sorted most recent first for chronological display.
    /// Rules are loaded once to enable efficient label lookups by rule ID.
    /// Any initialisation error from `SyncLogStore` is captured and displayed.
    private func refreshLogs() {
        loadError = nil
        rules = RuleStore().loadRules()

        do {
            let store = try SyncLogStore()
            logs = store.loadLogs().sorted { $0.timestamp > $1.timestamp }
        } catch {
            loadError = error.localizedDescription
            logs = []
        }
    }
}
