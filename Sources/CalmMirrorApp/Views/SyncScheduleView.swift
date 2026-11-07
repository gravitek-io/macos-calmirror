import CalmMirrorCore
import SwiftUI

/// Lets the user apply a background sync interval and see reload errors.
struct SyncScheduleView: View {
    @State private var selectedInterval = LaunchdManager.syncInterval
    @State private var appliedInterval = LaunchdManager.syncInterval
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Automatic sync") {
                Picker("Check calendars", selection: $selectedInterval) {
                    ForEach(LaunchdManager.allowedSyncIntervals, id: \.self) { seconds in
                        Text(seconds == 3600 ? "Every hour" : "Every \(seconds / 60) minutes").tag(seconds)
                    }
                }
                Text("Sync Now still runs immediately. Apply the schedule after any active sync finishes.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(isApplying ? "Applying…" : "Apply schedule") { applySchedule() }
                    .disabled(isApplying || selectedInterval == appliedInterval)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isApplying)
        .navigationTitle("Sync Schedule")
    }

    /// Reloads the launch agent away from the UI thread and commits the UI state on success.
    private func applySchedule() {
        let seconds = selectedInterval
        isApplying = true
        errorMessage = nil
        Task {
            let result = await Task.detached(priority: .utility) { () -> String? in
                do { try LaunchdManager().setSyncInterval(seconds); return nil }
                catch { return error.localizedDescription }
            }.value
            isApplying = false
            if let result { errorMessage = result }
            else { appliedInterval = seconds }
        }
    }
}
