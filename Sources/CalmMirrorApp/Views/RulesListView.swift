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

    /// Controls presentation of the rule editor sheet for adding or editing a rule.
    @State private var isEditorPresented = false

    /// The rule currently being edited, or `nil` when adding a new rule.
    @State private var ruleBeingEdited: MirrorRule?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if rules.isEmpty {
                    emptyStateView
                } else {
                    ruleListView
                }
            }
            .frame(minWidth: 480, minHeight: 260)
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentEditor(for: nil)
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .help("Add a new mirror rule")
                }
            }
            .onAppear {
                refreshRules()
            }
            .onChange(of: isEditorPresented) { _, isPresented in
                // Refresh the list when returning from the editor, regardless of
                // whether the user saved or cancelled, so any changes are visible.
                if !isPresented {
                    refreshRules()
                }
            }
            .navigationDestination(isPresented: $isEditorPresented) {
                RuleEditorView(
                    ruleStore: ruleStore,
                    existingRule: ruleBeingEdited
                )
            }
        }
    }

    // MARK: - Subviews

    /// Placeholder shown when no rules have been configured yet.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No rules configured")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Add Rule") {
                presentEditor(for: nil)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The main list of configured mirror rules.
    private var ruleListView: some View {
        List {
            ForEach(rules) { rule in
                ruleRow(for: rule)
            }
        }
    }

    /// A single row displaying a mirror rule's summary and action controls.
    ///
    /// Layout:
    /// - Leading: blocker label (primary) with optional warning badge when a
    ///   referenced calendar is unavailable (T049), source/target identifiers (secondary)
    /// - Trailing: window days badge, enable/disable toggle, edit button, delete button
    @ViewBuilder
    private func ruleRow(for rule: MirrorRule) -> some View {
        HStack(spacing: 12) {
            // Rule summary on the leading side
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.blockerLabel)
                        .font(.headline)
                        .lineLimit(1)

                    // Warning badge shown when a referenced calendar is unavailable (T049).
                    // The tooltip explains which calendar(s) can no longer be resolved.
                    if let warning = unavailableCalendarWarning(for: rule) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(warning)
                    }
                }

                Text("\(truncatedIdentifier(rule.sourceCalendarIdentifier)) → \(truncatedIdentifier(rule.targetCalendarIdentifier))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Window days badge
            Text("\(rule.windowDays)d")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())

            // Enable / disable toggle
            Toggle(isOn: toggleBinding(for: rule)) {
                // Label is intentionally empty; the toggle speaks for itself
                // alongside the row context.
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .help(rule.isEnabled ? "Disable rule" : "Enable rule")

            // Edit button
            Button {
                presentEditor(for: rule)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Edit rule")

            // Delete button
            Button(role: .destructive) {
                deleteRule(rule)
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    /// Returns the first 8 characters of a calendar identifier for compact display.
    ///
    /// Calendar identifiers are typically long UUIDs; showing only the prefix
    /// keeps the row visually clean while still being identifiable.
    ///
    /// - Parameter identifier: The full calendar identifier string.
    /// - Returns: A prefix of up to 8 characters.
    private func truncatedIdentifier(_ identifier: String) -> String {
        String(identifier.prefix(8))
    }

    /// Checks whether the source and/or target calendars referenced by a rule
    /// are still available in the system (T049).
    ///
    /// A calendar may become unavailable if the user removes the calendar,
    /// deletes the associated account, or has its access revoked by an
    /// administrator. This method uses `CalendarService.shared` to resolve
    /// each identifier and returns a human-readable warning message when
    /// one or both calendars are missing.
    ///
    /// - Parameter rule: The mirror rule whose calendar references to verify.
    /// - Returns: A warning message describing which calendar(s) are unavailable,
    ///   or `nil` if both calendars are still present.
    private func unavailableCalendarWarning(for rule: MirrorRule) -> String? {
        let sourceAvailable = CalendarService.shared.calendar(
            withIdentifier: rule.sourceCalendarIdentifier
        ) != nil
        let targetAvailable = CalendarService.shared.calendar(
            withIdentifier: rule.targetCalendarIdentifier
        ) != nil

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
        ruleBeingEdited = rule
        isEditorPresented = true
    }

    // MARK: - Store Operations

    /// Reloads the full rule list from the store into local state.
    private func refreshRules() {
        rules = ruleStore.loadRules()
    }

    /// Enables or disables a rule and refreshes the list.
    ///
    /// Errors are silently ignored here because the rule was just loaded from the
    /// same store and is expected to exist. A production-grade error surface
    /// (alert or toast) can be added in a future polish pass.
    ///
    /// - Parameters:
    ///   - rule: The rule to toggle.
    ///   - enabled: The desired enabled state.
    private func toggleRule(_ rule: MirrorRule, enabled: Bool) {
        do {
            if enabled {
                try ruleStore.enableRule(id: rule.id)
            } else {
                try ruleStore.disableRule(id: rule.id)
            }
        } catch {
            // Log-worthy but non-fatal; the refresh below will reconcile state.
        }
        refreshRules()
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
            // Non-fatal; refresh will reconcile.
        }
        refreshRules()
    }
}

