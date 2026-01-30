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
    var body: some View {
        TabView {
            RulesListView()
                .tabItem {
                    Label("Rules", systemImage: "list.bullet")
                }

            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
        }
        .frame(minWidth: 550, minHeight: 400)
    }
}
