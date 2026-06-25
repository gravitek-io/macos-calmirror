// RuleEditorView.swift
// CalmMirror — macOS Application
//
// Form view for creating or editing a MirrorRule (T023).
// Presents calendar pickers, a window-days input, and a blocker label
// text field. Validates input inline and persists changes through RuleStore.
//
// Requirements: macOS 14+ (Sonoma), Swift 5.10+

import CalmMirrorCore
import EventKit
import SwiftUI

/// A form view for creating a new mirror rule or editing an existing one.
///
/// The editor operates in two modes determined at initialization:
/// - **Create mode**: All form fields start with sensible defaults. On save,
///   a new `MirrorRule` is inserted via `RuleStore.addRule`.
/// - **Edit mode**: Form fields are pre-populated from the provided rule. On
///   save, the updated rule is persisted via `RuleStore.updateRule`.
///
/// Calendar pickers are populated from `CalendarService.shared.calendarsByAccount()`.
/// The source picker shows all calendars; the target picker shows only writable ones.
/// Inline validation prevents saving when source and target are identical or
/// when the blocker label is empty.
struct RuleEditorView: View {

    // MARK: - Mode

    /// The existing rule to edit, or `nil` when creating a new rule.
    private let existingRule: MirrorRule?

    /// Optional callback invoked after a successful save so the parent can refresh.
    private let onSave: (() -> Void)?

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Focus

    /// Identifies focusable text fields for programmatic focus management.
    ///
    /// SPM executables lack a bundle identifier, which can prevent automatic
    /// TextField focus. Using `@FocusState` lets us assign focus explicitly.
    private enum Field: Hashable {
        case title
        case windowDays
        case blockerLabel
    }

    /// The currently focused text field, or `nil` when no field has focus.
    @FocusState private var focusedField: Field?

    // MARK: - Form State

    /// Human-readable name identifying this rule.
    @State private var ruleTitle: String = ""

    /// Identifier of the selected source calendar.
    @State private var sourceCalendarID: String = ""

    /// Identifier of the selected target calendar.
    @State private var targetCalendarID: String = ""

    /// Number of days forward from today defining the sync window (1...120).
    @State private var windowDays: Int = 7

    /// Static label used as the blocker title when `usePlaceholder` is on.
    /// Empty by default for new rules; a suggestion is filled in when the user
    /// enables the placeholder.
    @State private var blockerLabel: String = ""

    /// Whether blockers use the static `blockerLabel` instead of mirroring the
    /// source event name. New rules default to mirroring the source name.
    @State private var usePlaceholder: Bool = false

    // MARK: - Calendar Data

    /// All calendars grouped by account, fetched on appear.
    @State private var calendarGroups: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])] = []

    /// Whether calendar access has been requested and granted.
    @State private var accessGranted: Bool = false

    /// Error message to display if calendar access is denied.
    @State private var accessError: String?

    /// Whether a save operation encountered an error.
    @State private var saveError: String?

    // MARK: - Dependencies

    /// Rule persistence store, shared with the parent view.
    private let ruleStore: RuleStore

    // MARK: - Initializers

    /// Creates a rule editor view.
    ///
    /// - Parameters:
    ///   - ruleStore: The store used to persist rule changes. Shared with the
    ///     parent to ensure a consistent view of persisted data.
    ///   - existingRule: An existing rule to edit, or `nil` to create a new one.
    ///   - onSave: Optional callback invoked after a successful save so the
    ///     parent can refresh its data immediately.
    init(
        ruleStore: RuleStore = RuleStore(),
        existingRule: MirrorRule? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.ruleStore = ruleStore
        self.existingRule = existingRule
        self.onSave = onSave

        // Pre-populate form state from existing rule when in edit mode.
        if let rule = existingRule {
            _ruleTitle = State(initialValue: rule.title)
            _sourceCalendarID = State(initialValue: rule.sourceCalendarIdentifier)
            _targetCalendarID = State(initialValue: rule.targetCalendarIdentifier)
            _windowDays = State(initialValue: rule.windowDays)
            _blockerLabel = State(initialValue: rule.blockerLabel)
            _usePlaceholder = State(initialValue: rule.usePlaceholder)
        }
    }

    // MARK: - Computed Properties

    /// Whether the editor is modifying an existing rule rather than creating one.
    private var isEditMode: Bool {
        existingRule != nil
    }

    /// Navigation title reflecting the current editing mode.
    private var navigationTitle: String {
        isEditMode ? "Edit Rule" : "New Rule"
    }

    /// Whether the rule title is empty or whitespace-only.
    private var isTitleEmpty: Bool {
        ruleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the source and target calendars are the same (self-mirroring).
    private var isSelfMirroring: Bool {
        !sourceCalendarID.isEmpty
            && !targetCalendarID.isEmpty
            && sourceCalendarID == targetCalendarID
    }

    /// Whether the blocker label is empty or whitespace-only.
    private var isLabelEmpty: Bool {
        blockerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Suggested default placeholder, prefixed with the rule title when present,
    /// e.g. "[Acme] Busy". Used to pre-fill the field when the user opts into the
    /// placeholder.
    private var suggestedPlaceholder: String {
        let trimmed = ruleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Busy" : "[\(trimmed)] Busy"
    }

    /// Example of a source-name blocker title, shown to explain the default mode.
    private var sourceNameExample: String {
        let trimmed = ruleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.isEmpty ? "[Rule]" : "[\(trimmed)]"
        return "\(prefix) <event name>"
    }

    /// Whether all form fields pass validation and the form can be saved.
    /// The label is only required when the placeholder is in use.
    private var isFormValid: Bool {
        !isTitleEmpty
            && !sourceCalendarID.isEmpty
            && !targetCalendarID.isEmpty
            && !isSelfMirroring
            && (!usePlaceholder || !isLabelEmpty)
            && (1...120).contains(windowDays)
    }

    /// Writable calendars flattened for the target picker, excluding the
    /// currently selected source calendar.
    private var writableCalendarGroups: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])] {
        calendarGroups.compactMap { group in
            let writable = group.calendars.filter { $0.writable }
            guard !writable.isEmpty else { return nil }
            return (account: group.account, calendars: writable)
        }
    }

    // MARK: - Body

    var body: some View {
        Form {
            calendarSection
            configurationSection
            validationSection
        }
        .formStyle(.grouped)
        .navigationTitle(navigationTitle)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isEditMode ? "Save" : "Create") {
                    performSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
            }
        }
        .task {
            await loadCalendars()
        }
        .onAppear {
            // Programmatically assign focus to the title field after
            // a short delay, giving the navigation transition time to settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .title
            }
        }
    }

    // MARK: - Sections

    /// Section for source and target calendar pickers.
    ///
    /// Pickers are only rendered after calendar data has loaded to avoid
    /// SwiftUI warnings about selection tags that don't match any option
    /// (the selection values are set before the async load completes).
    @ViewBuilder
    private var calendarSection: some View {
        Section("Calendars") {
            if !accessGranted && accessError == nil {
                // Calendar data is still loading; defer picker rendering.
                ProgressView("Loading calendars…")
            } else {
                // Source calendar picker: all calendars
                Picker("Source Calendar", selection: $sourceCalendarID) {
                    Text("Select a calendar")
                        .tag("")

                    ForEach(calendarGroups, id: \.account) { group in
                        Section(group.account) {
                            ForEach(group.calendars, id: \.calendar.calendarIdentifier) { entry in
                                Text("\(entry.calendar.title) (\(group.account))")
                                    .tag(entry.calendar.calendarIdentifier)
                            }
                        }
                    }
                }

                // Target calendar picker: only writable calendars
                Picker("Target Calendar", selection: $targetCalendarID) {
                    Text("Select a calendar")
                        .tag("")

                    ForEach(writableCalendarGroups, id: \.account) { group in
                        Section(group.account) {
                            ForEach(group.calendars, id: \.calendar.calendarIdentifier) { entry in
                                Text("\(entry.calendar.title) (\(group.account))")
                                    .tag(entry.calendar.calendarIdentifier)
                            }
                        }
                    }
                }

                // Inline error when source and target are the same
                if isSelfMirroring {
                    Text(MirrorRule.ValidationError.selfMirroring.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Section for rule title, window days input, and blocker label text field.
    @ViewBuilder
    private var configurationSection: some View {
        Section("Configuration") {
            TextField("Rule Title", text: $ruleTitle)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)

            // Inline error when title is empty
            if isTitleEmpty {
                Text(MirrorRule.ValidationError.emptyTitle.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Window")
                Spacer()
                TextField("", value: $windowDays, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .windowDays)
                Stepper("", value: $windowDays, in: 1...120)
                    .labelsHidden()
                Text("day\(windowDays == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }

            Toggle("Use a fixed placeholder", isOn: $usePlaceholder)
                .onChange(of: usePlaceholder) { _, isOn in
                    // Suggest a default placeholder the first time it's enabled.
                    if isOn && isLabelEmpty {
                        blockerLabel = suggestedPlaceholder
                    }
                }

            if usePlaceholder {
                TextField("Blocker Label", text: $blockerLabel)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .blockerLabel)

                // Inline error when label is empty in placeholder mode
                if isLabelEmpty {
                    Text(MirrorRule.ValidationError.emptyLabel.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Blockers will be titled “\(sourceNameExample)”, using each event's name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Section displaying access errors or save errors, if any.
    @ViewBuilder
    private var validationSection: some View {
        if let accessError {
            Section {
                Label(accessError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }

        if let saveError {
            Section {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    /// Requests calendar access and loads calendar groups for the pickers.
    private func loadCalendars() async {
        let status = CalendarService.shared.checkAuthorizationStatus()

        if status != .fullAccess {
            do {
                let granted = try await CalendarService.shared.requestAccess()
                if !granted {
                    accessError = "Calendar access was denied. Please grant access in System Settings > Privacy & Security > Calendars."
                    return
                }
            } catch {
                accessError = "Failed to request calendar access: \(error.localizedDescription)"
                return
            }
        }

        accessGranted = true
        calendarGroups = CalendarService.shared.calendarsByAccount()
    }

    /// Validates and persists the rule, then dismisses the editor.
    private func performSave() {
        saveError = nil

        if isEditMode, let existing = existingRule {
            // Edit mode: update mutable fields on the existing rule.
            var updated = existing
            updated.title = ruleTitle
            updated.windowDays = windowDays
            updated.blockerLabel = blockerLabel
            updated.usePlaceholder = usePlaceholder
            updated.updatedAt = Date()

            // Source and target are immutable (let properties), so they cannot
            // be changed in edit mode. A new rule must be created instead.

            do {
                try ruleStore.updateRule(updated)
                onSave?()
                dismiss()
            } catch {
                saveError = "Failed to save rule: \(error.localizedDescription)"
            }
        } else {
            // Create mode: verify the target calendar is still writable.
            // The picker only shows writable calendars, but the calendar's
            // permissions may have changed between picker population and save.
            guard let targetCalendar = CalendarService.shared.calendar(withIdentifier: targetCalendarID),
                  targetCalendar.allowsContentModifications else {
                saveError = "The selected target calendar is no longer writable. Please choose a different target calendar."
                return
            }

            // Build a new MirrorRule and add it to the store.
            let newRule = MirrorRule(
                title: ruleTitle,
                sourceCalendarIdentifier: sourceCalendarID,
                targetCalendarIdentifier: targetCalendarID,
                windowDays: windowDays,
                blockerLabel: blockerLabel,
                usePlaceholder: usePlaceholder
            )

            do {
                try ruleStore.addRule(newRule)
                onSave?()
                dismiss()
            } catch {
                saveError = "Failed to create rule: \(error.localizedDescription)"
            }
        }
    }
}
