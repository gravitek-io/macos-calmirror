// RulesListView.swift
// CalmMirror — macOS Menu Bar Application
//
// Displays all configured mirror rules with options to add, edit,
// enable/disable, and delete (T022).
// Detects and warns when a referenced calendar becomes unavailable (T049).

import CalmMirrorCore
import EventKit
import SwiftUI

/// Displays all configured mirror rules with options to add, edit, enable/disable, and delete.
///
/// This view is presented in the Settings window and serves as the primary
/// rule management interface. Each rule shows its label, source/target info,
/// window days, and an enable/disable toggle.
///
/// Mutations (add, edit, delete, toggle) are persisted immediately via `RuleStore`
/// and the displayed list is refreshed after each operation.
struct RulesListView: View {

    // MARK: - State

    /// Store instance used to load and persist mirror rules.
    @State private var ruleStore = RuleStore()

    /// The current snapshot of all persisted rules, refreshed after every mutation.
    @State private var rules: [MirrorRule] = []

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let rule: MirrorRule?
    }
    @State private var editorRequest: EditorRequest?

    /// Shared coordinator used to trigger syncs and read per-rule outcomes.
    @Environment(SyncCoordinator.self) private var syncCoordinator

    /// Whether at least one rule is enabled, i.e. a sync would do something.
    private var hasEnabledRule: Bool {
        rules.contains(where: \.isEnabled)
    }

    @State private var searchText = ""
    @State private var filter = "All"
    @State private var ruleToDelete: MirrorRule?
    @State private var operationError: String?
    @State private var rulesReadError: String?

    private var visibleRules: [MirrorRule] {
        rules.filter { rule in
            let matchesStatus = filter == "All" || (filter == "Active" ? rule.isEnabled : !rule.isEnabled)
            let searchable = [rule.title, calendarName(rule.sourceCalendarIdentifier),
                              calendarName(rule.targetCalendarIdentifier)].joined(separator: " ")
            return matchesStatus && (searchText.isEmpty || searchable.localizedCaseInsensitiveContains(searchText))
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "Mirror Rules", subtitle: "Choose where your availability is shared.")
                HStack(spacing: 8) {
                    StatusPill(title: "\(rules.filter(\.isEnabled).count) active", symbol: "circle.fill", color: .green)
                    StatusPill(title: "\(rules.filter { !$0.isEnabled }.count) paused", symbol: "pause.fill")
                    Spacer()
                    Picker("Show rules", selection: $filter) {
                        ForEach(["All", "Active", "Paused"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 200)
                }
            }
            .padding(24)
            if let rulesReadError {
                ContentUnavailableView {
                    Label("Couldn’t read mirror rules", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(rulesReadError)
                } actions: {
                    Button("Try Again") { refreshRules() }
                }
            } else if rules.isEmpty {
                ContentUnavailableView {
                    Label("Connect your calendars", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Create a rule to copy busy time from one calendar to another.")
                } actions: {
                    Button("Create a Rule", systemImage: "plus") { presentEditor(for: nil) }
                        .buttonStyle(.borderedProminent)
                }
            } else if visibleRules.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleRules) { rule in ruleRow(for: rule) }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Mirror Rules")
        .searchable(text: $searchText, prompt: "Find a rule or calendar")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { syncCoordinator.requestSync() } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .help(syncNowHelp)
                .disabled(syncCoordinator.isSyncing || !hasEnabledRule)
                Button { presentEditor(for: nil) } label: {
                    Label("New Rule", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Create a mirror rule")
            }
        }
        .onAppear { refreshRules(); syncCoordinator.refresh() }
        .sheet(item: $editorRequest, onDismiss: refreshRules) { request in
            NavigationStack {
                RuleEditorView(ruleStore: ruleStore, existingRule: request.rule,
                               onSave: { refreshRules(); syncCoordinator.requestSync() })
            }
            .frame(width: 570, height: 700)
        }
        .confirmationDialog("Delete this mirror rule?", isPresented: Binding(
            get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }
        ), titleVisibility: .visible) {
            if let rule = ruleToDelete {
                Button("Delete Rule", role: .destructive) { deleteRule(rule); ruleToDelete = nil }
            }
        } message: {
            Text("Its managed Busy blocks will be removed. Original calendar events will stay in place.")
        }
        .alert("Couldn’t update rule", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) { Button("OK") { operationError = nil } } message: { Text(operationError ?? "") }
    }

    private func calendarName(_ id: String) -> String {
        CalendarService.shared.calendar(withIdentifier: id)?.title ?? "Unavailable calendar"
    }

    private func calendarColor(_ calendar: EKCalendar?) -> Color {
        guard let color = calendar?.cgColor else { return .secondary }
        return Color(cgColor: color)
    }

    /// Resolve each endpoint once for a consistent card snapshot, without
    /// retaining EventKit objects across render passes.
    private func ruleRow(for rule: MirrorRule) -> some View {
        let source = CalendarService.shared.calendar(withIdentifier: rule.sourceCalendarIdentifier)
        let target = CalendarService.shared.calendar(withIdentifier: rule.targetCalendarIdentifier)
        return RuleCard(title: rule.title,
                 sourceName: source?.title ?? "Unavailable calendar",
                 sourceAccount: source?.source?.title ?? "Check calendar access",
                 sourceColor: calendarColor(source),
                 targetName: target?.title ?? "Unavailable calendar",
                 targetAccount: target?.source?.title ?? "Check calendar access",
                 targetColor: calendarColor(target),
                 days: rule.windowDays, isEnabled: rule.isEnabled,
                 isPrivate: rule.usePlaceholder, allowsChaining: false) {
            Toggle("Enable \(rule.title)", isOn: toggleBinding(for: rule))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
            Menu {
                Button("Edit Rule", systemImage: "pencil") { presentEditor(for: rule) }
                Divider()
                Button("Delete Rule…", systemImage: "trash", role: .destructive) { ruleToDelete = rule }
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Rule actions")
            .accessibilityLabel("Actions for \(rule.title)")
        } status: {
            if let warning = unavailableCalendarWarning(sourceAvailable: source != nil, targetAvailable: target != nil) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                lastSyncCaption(for: rule)
            }
        }
        .contextMenu {
            Button("Edit Rule", systemImage: "pencil") { presentEditor(for: rule) }
            Button("Delete Rule…", systemImage: "trash", role: .destructive) { ruleToDelete = rule }
        }
    }

    /// One-line summary of the rule's most recent sync, from the log store.
    ///
    /// Shows when it ran and what it changed, or the first error in red, so
    /// a user who "sees no sync" can tell at a glance whether the agent ever
    /// processed the rule. Rules that never synced say so explicitly.
    @ViewBuilder
    private func lastSyncCaption(for rule: MirrorRule) -> some View {
        if let log = syncCoordinator.latestLogByRule[rule.id] {
            if let error = log.errors.first {
                HStack(spacing: 4) {
                    Text("Last sync failed")
                    RelativeTimeText(date: log.timestamp)
                    Text("· \(error.message)")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(error.message)
            } else {
                HStack(spacing: 4) {
                    Text("Last synced")
                    RelativeTimeText(date: log.timestamp)
                    Text("· \(changeSummary(for: log))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } else {
            Text("Not synced yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    /// Tooltip of the "Sync Now" button, explaining why it is disabled when it is.
    private var syncNowHelp: String {
        if syncCoordinator.isSyncing {
            return "A sync is in progress"
        }
        if !hasEnabledRule {
            return "Enable a rule to sync"
        }
        return "Run the sync agent now instead of waiting for the schedule"
    }

    /// Builds a compact "+N added, ~N updated, -N removed" summary for a log.
    private func changeSummary(for log: SyncLog) -> String {
        "+\(log.addedCount) added, ~\(log.updatedCount) updated, -\(log.removedCount) removed"
    }

    /// Describes availability using the same endpoint snapshot shown on the card.
    private func unavailableCalendarWarning(sourceAvailable: Bool, targetAvailable: Bool) -> String? {
        switch (sourceAvailable, targetAvailable) {
        case (true, true):
            return nil
        case (false, true):
            return "Source calendar is no longer available."
        case (true, false):
            return "Target calendar is no longer available."
        case (false, false):
            return "Both source and target calendars are no longer available."
        }
    }

    /// Creates a `Binding<Bool>` that toggles the enabled state of a specific rule.
    ///
    /// On change, the binding calls `enableRule` or `disableRule` on the store
    /// and refreshes the local rules array so the UI stays in sync.
    ///
    /// - Parameter rule: The rule whose `isEnabled` state should be toggled.
    /// - Returns: A binding suitable for use with `Toggle`.
    private func toggleBinding(for rule: MirrorRule) -> Binding<Bool> {
        Binding<Bool>(
            get: { rule.isEnabled },
            set: { newValue in
                toggleRule(rule, enabled: newValue)
            }
        )
    }

    /// Presents the rule editor sheet, optionally in edit mode for an existing rule.
    ///
    /// - Parameter rule: The rule to edit, or `nil` to create a new one.
    private func presentEditor(for rule: MirrorRule?) {
        editorRequest = EditorRequest(rule: rule)
    }

    // MARK: - Store Operations

    /// Reloads the full rule list from the store into local state.
    private func refreshRules() {
        do {
            rules = ruleStore.loadRules()
            rulesReadError = nil
        } catch {
            rulesReadError = error.localizedDescription
        }
    }

    /// Enables or disables a rule and refreshes the list.
    ///
    /// - Parameters:
    ///   - rule: The rule to toggle.
    ///   - enabled: The desired enabled state.
    private func toggleRule(_ rule: MirrorRule, enabled: Bool) {
        var didUpdate = false
        do {
            if enabled {
                try ruleStore.enableRule(id: rule.id)
            } else {
                try ruleStore.disableRule(id: rule.id)
            }
            didUpdate = true
        } catch {
            operationError = error.localizedDescription
        }
        refreshRules()

        // Re-enabling a rule is like creating it: sync right away so its
        // blockers come back without waiting for the schedule.
        if didUpdate && enabled {
            syncCoordinator.requestSync()
        }
    }

    /// Removes a rule and its associated blocker events, then refreshes the list.
    ///
    /// Delegates to `removeRuleWithCleanup` which cascade-deletes all managed
    /// blocker events from the target calendar and removes the sync record file
    /// before deleting the rule configuration itself (T042).
    ///
    /// - Parameter rule: The rule to delete.
    private func deleteRule(_ rule: MirrorRule) {
        do {
            let syncRecordStore = try SyncRecordStore()
            try ruleStore.removeRuleWithCleanup(
                id: rule.id,
                syncRecordStore: syncRecordStore,
                calendarService: CalendarService.shared
            )
        } catch {
            operationError = error.localizedDescription
        }
        refreshRules()
    }
}

