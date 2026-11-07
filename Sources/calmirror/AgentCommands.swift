import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

// MARK: - Agent Subcommand Group

extension CalmMirror {

    /// Parent command for launchd agent management subcommands.
    ///
    /// The agent runs `calmirror sync` every 15 minutes in the background
    /// via a macOS launchd user agent. This command group provides install,
    /// uninstall, and status operations for the agent plist.
    ///
    /// Usage:
    /// ```
    /// calmirror agent                # show agent status (default)
    /// calmirror agent install        # install and start the agent
    /// calmirror agent uninstall      # stop and remove the agent
    /// calmirror agent status         # show agent status
    /// calmirror agent status --json  # show agent status as JSON
    /// ```
    struct Agent: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Manage the background sync agent",
            subcommands: [
                AgentInstall.self,
                AgentUninstall.self,
                AgentStatus.self
            ],
            defaultSubcommand: AgentStatus.self
        )
    }
}

// MARK: - Agent Install

extension CalmMirror.Agent {

    /// Installs the launchd agent plist and loads it into the current user session.
    ///
    /// The agent is configured to run `calmirror sync` every 15 minutes as
    /// a background process. It starts automatically at login and persists
    /// when the GUI application is closed.
    ///
    /// If the agent is already installed, prints a message and exits with
    /// code 0 (no-op).
    ///
    /// Exit codes:
    /// - 0: Agent installed successfully, or already installed
    /// - 1: Plist written but launchctl bootstrap failed
    /// - 2: Plist write failed
    struct AgentInstall: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install and start the background sync agent"
        )

        func run() throws {
            let launchdManager = LaunchdManager()

            // If already installed, inform the user and exit cleanly.
            if launchdManager.isInstalled() {
                print(
                    "Agent is already installed and running. "
                    + "Use 'calmirror agent uninstall' first to reinstall."
                )
                return
            }

            // Resolve the CLI binary path from the current process.
            let cliPath = (CommandLine.arguments[0] as NSString).resolvingSymlinksInPath

            do {
                try launchdManager.install(cliPath: cliPath)
            } catch let error as LaunchdManagerError {
                switch error {
                case .plistWriteFailed(let detail):
                    writeToStderr("error: \(detail)")
                    Darwin.exit(2)
                case .launchctlFailed(let detail):
                    writeToStderr(
                        "error: plist written but launchctl bootstrap failed: \(detail). "
                        + "Try manually: launchctl bootstrap gui/\(getuid()) \(launchdManager.plistURL().path)"
                    )
                    Darwin.exit(1)
                case .alreadyInstalled:
                    // Should not reach here due to the guard above,
                    // but handle gracefully.
                    print(
                        "Agent is already installed and running. "
                        + "Use 'calmirror agent uninstall' first to reinstall."
                    )
                    return
                case .notInstalled:
                    // Should not occur during install.
                    writeToStderr("error: unexpected state during install.")
                    Darwin.exit(2)
                }
            }

            // Print confirmation with details.
            let plistPath = launchdManager.plistURL().path
            let intervalMinutes = LaunchdManager.syncInterval / 60

            print("Agent installed and loaded.")
            print("  Plist:    \(plistPath)")
            print("  Interval: every \(intervalMinutes) minutes")
            print("  Status:   running")
        }
    }
}

// MARK: - Agent Uninstall

extension CalmMirror.Agent {

    /// Unloads the launchd agent and removes its plist file.
    ///
    /// If the agent is not installed, prints an error to stderr and exits
    /// with code 2.
    ///
    /// Exit codes:
    /// - 0: Agent unloaded and plist removed
    /// - 1: Partial uninstall (bootout failed but plist removed, or vice versa)
    /// - 2: Agent was not installed
    struct AgentUninstall: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Stop and remove the background sync agent"
        )

        func run() throws {
            let launchdManager = LaunchdManager()

            // Verify the agent is installed before attempting uninstall.
            guard launchdManager.isInstalled() else {
                writeToStderr("error: agent is not installed. Nothing to uninstall.")
                Darwin.exit(2)
            }

            do {
                try launchdManager.uninstall()
            } catch let error as LaunchdManagerError {
                switch error {
                case .launchctlFailed(let detail):
                    // Bootout failed but plist may have been removed.
                    writeToStderr("warning: launchctl bootout failed: \(detail). Plist removed anyway.")
                    Darwin.exit(1)
                case .plistWriteFailed(let detail):
                    // Plist removal failed.
                    writeToStderr("error: \(detail)")
                    Darwin.exit(1)
                case .notInstalled:
                    writeToStderr("error: agent is not installed. Nothing to uninstall.")
                    Darwin.exit(2)
                case .alreadyInstalled:
                    writeToStderr("error: unexpected state during uninstall.")
                    Darwin.exit(1)
                }
            }

            print("Agent unloaded and removed.")
        }
    }
}

// MARK: - Agent Status

extension CalmMirror.Agent {

    /// Displays the current status of the launchd sync agent.
    ///
    /// Shows whether the agent is installed, running, its PID, plist
    /// location, and the configured sync interval. Supports both
    /// human-readable and JSON output.
    ///
    /// Exit codes:
    /// - 0: Always (status is informational)
    struct AgentStatus: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the background sync agent status"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            let launchdManager = LaunchdManager()
            let agentStatus = launchdManager.status()

            if json {
                printAgentStatusJSON(agentStatus)
            } else {
                printAgentStatusHuman(agentStatus)
            }
        }

        /// Prints agent status in a human-readable format.
        ///
        /// Example output:
        /// ```
        /// Agent Status
        ///   Installed: yes
        ///   Running:   yes (PID 12345)
        ///   Plist:     ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist
        ///   Interval:  900s (15 minutes)
        /// ```
        private func printAgentStatusHuman(_ status: LaunchdAgentStatus) {
            let installedText = status.installed ? "yes" : "no"
            let runningText: String
            if status.running, let pid = status.pid {
                runningText = "yes (PID \(pid))"
            } else if status.running {
                runningText = "yes"
            } else {
                runningText = "no"
            }

            let intervalMinutes = status.intervalSeconds / 60

            print("Agent Status")
            print("  Installed: \(installedText)")
            print("  Running:   \(runningText)")
            print("  Plist:     \(status.plistPath)")
            print("  Interval:  \(status.intervalSeconds)s (\(intervalMinutes) minutes)")
        }

        /// Prints agent status as a JSON object.
        ///
        /// Includes installation state, running state, PID, plist path,
        /// and the configured interval in seconds.
        private func printAgentStatusJSON(_ status: LaunchdAgentStatus) {
            var result: [String: Any] = [
                "installed": status.installed,
                "running": status.running,
                "plistPath": status.plistPath,
                "intervalSeconds": status.intervalSeconds
            ]

            if let pid = status.pid {
                result["pid"] = pid
            } else {
                result["pid"] = NSNull()
            }

            if let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                print("{}")
            }
        }
    }
}
