// CalmMirrorApp.swift
// CalmMirror — macOS Application
//
// Main entry point for the CalmMirror configuration app.
// Provides a standard window with tabs for rule management and sync logs.
// The app can be closed when not needed — background sync is handled
// entirely by the launchd daemon running `calmirror sync`.
//
// Requirements: macOS 26+, Swift 6.2+

import AppKit
import CalmMirrorCore
import SwiftUI

/// Application delegate that configures the process as a regular macOS app.
///
/// SPM executables lack an embedded Info.plist and bundle identifier, causing
/// macOS to treat them as accessory processes with broken window focus. This
/// delegate sets the activation policy to `.regular` early in the launch cycle
/// so that windows receive proper key-window status, first-responder management,
/// and TextField focus.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The main application entry point for CalmMirror.
///
/// CalmMirror is a standard windowed application used to configure mirror
/// rules and review sync logs. It can be quit freely — background sync is
/// handled by the launchd agent (`calmirror sync`) independently.
///
/// The main window presents a ``TabView`` with two tabs:
/// - **Rules**: manage mirror rule configuration via ``RulesListView``.
/// - **Logs**: review sync execution history via ``LogsView``.
@main
struct CalmMirrorApp: App {

    /// Delegate that sets the activation policy before windows are created.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Body

    var body: some Scene {
        WindowGroup("CalMirror") {
            ContentView()
        }
        .defaultSize(width: 600, height: 450)
    }
}

/// Root content view hosting the tab interface.
///
/// Separated from the `App` struct to allow the `.onAppear` activation
/// modifier to fire reliably on first window presentation.
private struct ContentView: View {

    /// The tabs of the main window, in display order.
    private enum Tab: Hashable {
        case rules
        case logs
    }

    /// Shared coordinator for on-demand syncs, injected into the environment
    /// so the rules tab, the footer and the editor observe the same state.
    @State private var syncCoordinator = SyncCoordinator()

    /// The selected tab, owned explicitly rather than left to `TabView`.
    ///
    /// Without a selection binding, the macOS `TabView` reverts to the
    /// previous tab when the newly shown tab mutates its state while
    /// appearing, which ``LogsView`` does when it loads the logs. The first
    /// click on "Logs" then appears to do nothing; holding the selection
    /// here makes it the single source of truth and keeps the switch.
    @State private var selectedTab: Tab = .rules

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                RulesListView()
                    .tabItem {
                        Label("Rules", systemImage: "list.bullet")
                    }
                    .tag(Tab.rules)

                LogsView()
                    .tabItem {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .tag(Tab.logs)
            }

            Divider()
            WindowFooter()
        }
        .frame(minWidth: 550, minHeight: 400)
        .environment(syncCoordinator)
        .onAppear {
            syncCoordinator.refresh()
        }
    }
}

/// Discreet footer showing the application name and version on the left and
/// the sync status on the right.
///
/// The version lets users report the exact build they run without opening
/// the About panel. It comes from the bundle's `CFBundleShortVersionString`;
/// when the binary runs outside a bundle (`swift run`), it falls back to the
/// core library version so the footer never shows an empty value.
///
/// The sync status answers "is anything happening?" from any tab: a spinner
/// while a triggered run is in progress, the last failure, or how long ago
/// the last sync ran (whether triggered by the app or by the schedule).
private struct WindowFooter: View {
    private static let versionString: String = {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return bundleVersion ?? CalmMirrorCore.version
    }()

    @Environment(SyncCoordinator.self) private var syncCoordinator

    var body: some View {
        HStack {
            Text("CalMirror \(Self.versionString)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            syncStatus
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// The right-hand status: syncing, failed, last sync time or none yet.
    @ViewBuilder
    private var syncStatus: some View {
        if syncCoordinator.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = syncCoordinator.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .truncationMode(.tail)
                .help(error)
        } else if let lastSync = syncCoordinator.lastSyncDate {
            HStack(spacing: 4) {
                Text("Last sync:")
                RelativeTimeText(date: lastSync)
            }
            .foregroundStyle(.secondary)
        } else {
            Text("No sync yet")
                .foregroundStyle(.secondary)
        }
    }
}
