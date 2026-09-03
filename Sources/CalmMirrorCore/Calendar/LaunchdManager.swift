import Foundation

// MARK: - LaunchdManagerError

/// Errors that can occur during launchd agent management operations.
public enum LaunchdManagerError: Error, LocalizedError {

    /// The agent plist is already installed at the expected path.
    case alreadyInstalled

    /// The agent plist was not found at the expected path.
    case notInstalled

    /// Failed to write the plist file to disk.
    case plistWriteFailed(String)

    /// A `launchctl` command exited with a non-zero status.
    case launchctlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInstalled:
            return "The CalmMirror sync agent is already installed."
        case .notInstalled:
            return "The CalmMirror sync agent is not installed."
        case .plistWriteFailed(let detail):
            return "Failed to write agent plist: \(detail)"
        case .launchctlFailed(let detail):
            return "launchctl command failed: \(detail)"
        }
    }
}

// MARK: - AgentStatus

/// Describes the current state of the CalmMirror launchd sync agent.
///
/// Returned by ``LaunchdManager/status()`` to provide a snapshot of
/// whether the agent is installed, running, and its configuration details.
public struct AgentStatus {

    /// Whether the agent plist file exists at ~/Library/LaunchAgents/.
    public let installed: Bool

    /// Whether the agent process is currently loaded and running.
    public let running: Bool

    /// The PID of the running agent process, if available.
    public let pid: Int?

    /// The full path to the agent plist file.
    public let plistPath: String

    /// The configured sync interval in seconds.
    public let intervalSeconds: Int

    /// Creates a new agent status snapshot.
    ///
    /// - Parameters:
    ///   - installed: Whether the plist file exists on disk.
    ///   - running: Whether the agent process is loaded and running.
    ///   - pid: The PID of the running agent, or `nil` if not running.
    ///   - plistPath: The full path to the agent plist file.
    ///   - intervalSeconds: The configured sync interval in seconds.
    public init(
        installed: Bool,
        running: Bool,
        pid: Int?,
        plistPath: String,
        intervalSeconds: Int
    ) {
        self.installed = installed
        self.running = running
        self.pid = pid
        self.plistPath = plistPath
        self.intervalSeconds = intervalSeconds
    }
}

// MARK: - LaunchdManager

/// Manages the launchd agent that runs `calmirror sync` on a 15-minute schedule.
///
/// The agent plist is installed at `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist`
/// and uses modern `launchctl bootstrap/bootout` commands for loading and unloading.
///
/// ## Lifecycle
/// 1. Call ``install(cliPath:)`` to write the plist and bootstrap the agent.
/// 2. Call ``status()`` to inspect whether the agent is installed and running.
/// 3. Call ``uninstall()`` to bootout the agent and remove the plist.
///
/// ## Permissions
/// The plist file is written with POSIX permissions `0o644` (owner read/write,
/// group and others read-only), which is the standard for LaunchAgent plists.
public final class LaunchdManager {

    // MARK: - Constants

    /// The launchd service label used to identify the agent.
    public static let serviceLabel = "com.gravitek.calmirror.sync"

    /// The plist filename written to ~/Library/LaunchAgents/.
    public static let plistFilename = "com.gravitek.calmirror.sync.plist"

    /// Sync interval in seconds (15 minutes).
    public static let syncInterval = 900

    /// Path for the agent's stdout log output.
    private static let stdoutLogPath = "/tmp/calmirror.stdout.log"

    /// Path for the agent's stderr log output.
    private static let stderrLogPath = "/tmp/calmirror.stderr.log"

    // MARK: - Initialization

    /// Creates a new launchd manager instance.
    public init() {}

    // MARK: - Plist Location

    /// Returns the URL of the agent plist file in ~/Library/LaunchAgents/.
    ///
    /// The path is computed from the current user's home directory so that
    /// it works correctly regardless of the user account running the process.
    ///
    /// - Returns: The file URL for the agent plist.
    public func plistURL() -> URL {
        let launchAgentsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        return launchAgentsDir.appendingPathComponent(Self.plistFilename)
    }

    // MARK: - Installation Check

    /// Checks whether the agent plist file exists at the expected path.
    ///
    /// This only verifies file existence; it does not check whether the
    /// agent is actually loaded or running. Use ``status()`` for a complete
    /// picture.
    ///
    /// - Returns: `true` if the plist file exists on disk.
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL().path)
    }

    // MARK: - Install

    /// Installs and bootstraps the CalmMirror sync agent.
    ///
    /// This method performs the following steps:
    /// 1. Checks that the agent is not already installed.
    /// 2. Resolves the CLI binary path (explicit or auto-detected).
    /// 3. Generates the launchd plist XML content.
    /// 4. Creates the ~/Library/LaunchAgents/ directory if needed.
    /// 5. Writes the plist file with permissions `0o644`.
    /// 6. Bootstraps the agent into the current GUI domain via `launchctl`.
    ///
    /// - Parameter cliPath: An explicit path to the `calmirror` binary.
    ///   If `nil`, the path is auto-detected from the current process arguments.
    /// - Throws: ``LaunchdManagerError/alreadyInstalled`` if the plist already exists,
    ///   ``LaunchdManagerError/plistWriteFailed(_:)`` if the file cannot be written,
    ///   or ``LaunchdManagerError/launchctlFailed(_:)`` if bootstrapping fails.
    public func install(cliPath: String? = nil) throws {
        // Prevent double-installation.
        guard !isInstalled() else {
            throw LaunchdManagerError.alreadyInstalled
        }

        // Resolve the CLI binary path for the ProgramArguments entry.
        let resolvedPath = try resolveCLIPath(explicit: cliPath)

        // Generate the plist XML content.
        let plistContent = generatePlistContent(cliPath: resolvedPath)

        // Ensure the LaunchAgents directory exists.
        let plistFileURL = plistURL()
        let launchAgentsDir = plistFileURL.deletingLastPathComponent()
        try createDirectoryIfNeeded(at: launchAgentsDir)

        // Write the plist file with standard 644 permissions.
        try writePlistFile(content: plistContent, to: plistFileURL)

        // Bootstrap the agent into the current user's GUI domain.
        try bootstrapAgent(plistPath: plistFileURL.path)
    }

    // MARK: - Uninstall

    /// Uninstalls the CalmMirror sync agent.
    ///
    /// This method performs the following steps:
    /// 1. Verifies the agent plist exists on disk.
    /// 2. Attempts to bootout the agent from the current GUI domain.
    /// 3. Removes the plist file from disk.
    ///
    /// Launchctl errors during bootout are intentionally ignored because the
    /// agent may not be loaded even though the plist file exists (e.g., after
    /// a system restart where the agent failed to load).
    ///
    /// - Throws: ``LaunchdManagerError/notInstalled`` if the plist does not exist.
    public func uninstall() throws {
        guard isInstalled() else {
            throw LaunchdManagerError.notInstalled
        }

        let uid = currentUID()
        let serviceTarget = "gui/\(uid)/\(Self.serviceLabel)"

        // Attempt to bootout the agent. Errors are non-fatal because
        // the agent may not be loaded even if the plist file exists.
        let bootoutProcess = Process()
        bootoutProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootoutProcess.arguments = ["bootout", serviceTarget]
        bootoutProcess.standardOutput = FileHandle.nullDevice
        bootoutProcess.standardError = FileHandle.nullDevice

        try? bootoutProcess.run()
        bootoutProcess.waitUntilExit()

        // Remove the plist file regardless of bootout outcome.
        do {
            try FileManager.default.removeItem(at: plistURL())
        } catch {
            throw LaunchdManagerError.plistWriteFailed(
                "Failed to remove plist file: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Status

    /// Returns a snapshot of the agent's current state.
    ///
    /// Checks file existence for the installation status and runs
    /// `launchctl print` to determine whether the agent is loaded
    /// and running, including its PID if available.
    ///
    /// - Returns: An ``AgentStatus`` describing the agent's current state.
    public func status() -> AgentStatus {
        let installed = isInstalled()
        var running = false
        var pid: Int? = nil

        if installed {
            (running, pid) = queryAgentRunState()
        }

        return AgentStatus(
            installed: installed,
            running: running,
            pid: pid,
            plistPath: plistURL().path,
            intervalSeconds: Self.syncInterval
        )
    }

    // MARK: - Kickstart

    /// Asks launchd to run the sync agent immediately, outside its schedule.
    ///
    /// Runs `launchctl kickstart gui/<uid>/com.gravitek.calmirror.sync`. This
    /// is how the app offers a "Sync Now" action without embedding its own
    /// copy of the sync run: the agent stays the single process that writes
    /// to the calendars, and launchd guarantees that only one instance of the
    /// job runs at a time (a kickstart issued while the job is already
    /// running is ignored, the running instance simply completes).
    ///
    /// The call returns as soon as launchd has accepted the request; it does
    /// not wait for the sync to finish. Callers observe completion through
    /// ``status()`` and the sync logs.
    ///
    /// - Throws: ``LaunchdManagerError/notInstalled`` if the agent plist is
    ///   missing, or ``LaunchdManagerError/launchctlFailed(_:)`` if launchd
    ///   rejects the request (for example when the agent is not loaded).
    public func kickstart() throws {
        guard isInstalled() else {
            throw LaunchdManagerError.notInstalled
        }

        let serviceTarget = "gui/\(currentUID())/\(Self.serviceLabel)"
        try runLaunchctl(["kickstart", serviceTarget])
    }

    // MARK: - Private Helpers

    /// Returns the current user's numeric UID as a string.
    ///
    /// Used to construct the `gui/<uid>` domain target for `launchctl`
    /// bootstrap and bootout commands.
    ///
    /// - Returns: The UID of the current process owner.
    private func currentUID() -> String {
        String(getuid())
    }

    /// Resolves the path to the `calmirror` CLI binary.
    ///
    /// If an explicit path is provided, it is used directly after verifying
    /// the file exists. Otherwise, the path is auto-detected from
    /// `CommandLine.arguments[0]`, resolving any symlinks to get the
    /// canonical path.
    ///
    /// - Parameter explicit: An explicit path provided by the caller, or `nil`.
    /// - Returns: The resolved absolute path to the CLI binary.
    /// - Throws: ``LaunchdManagerError/plistWriteFailed(_:)`` if the binary
    ///   cannot be found at the resolved path.
    private func resolveCLIPath(explicit: String?) throws -> String {
        if let explicit = explicit {
            // Use the explicitly provided path, resolving symlinks.
            let resolved = (explicit as NSString).resolvingSymlinksInPath
            guard FileManager.default.fileExists(atPath: resolved) else {
                throw LaunchdManagerError.plistWriteFailed(
                    "CLI binary not found at specified path: \(resolved)"
                )
            }
            return resolved
        }

        // Auto-detect from the current process arguments.
        let rawPath = CommandLine.arguments[0]
        let resolved = (rawPath as NSString).resolvingSymlinksInPath

        guard FileManager.default.fileExists(atPath: resolved) else {
            throw LaunchdManagerError.plistWriteFailed(
                "CLI binary not found at auto-detected path: \(resolved). "
                + "Provide an explicit path using the --cli-path option."
            )
        }

        return resolved
    }

    /// Generates the XML plist content for the launchd agent.
    ///
    /// The generated plist configures:
    /// - **Label**: The service identifier for launchctl operations.
    /// - **ProgramArguments**: The CLI binary path followed by the `sync` subcommand.
    /// - **StartInterval**: How often (in seconds) the agent runs.
    /// - **ProcessType**: Set to `Background` to indicate low-priority background work.
    /// - **RunAtLoad**: Starts the first sync immediately when the agent loads.
    /// - **StandardOutPath / StandardErrorPath**: Log file locations for debugging.
    ///
    /// - Parameter cliPath: The resolved absolute path to the `calmirror` binary.
    /// - Returns: The plist XML content as a string.
    private func generatePlistContent(cliPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.serviceLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(cliPath)</string>
                <string>sync</string>
            </array>
            <key>StartInterval</key>
            <integer>\(Self.syncInterval)</integer>
            <key>ProcessType</key>
            <string>Background</string>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(Self.stdoutLogPath)</string>
            <key>StandardErrorPath</key>
            <string>\(Self.stderrLogPath)</string>
        </dict>
        </plist>
        """
    }

    /// Creates a directory at the given URL if it does not already exist.
    ///
    /// - Parameter url: The directory URL to create.
    /// - Throws: ``LaunchdManagerError/plistWriteFailed(_:)`` if directory
    ///   creation fails.
    private func createDirectoryIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return // Directory already exists.
            }
            throw LaunchdManagerError.plistWriteFailed(
                "A file (not a directory) exists at \(url.path)."
            )
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw LaunchdManagerError.plistWriteFailed(
                "Failed to create directory at \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Writes the plist content to disk with POSIX permissions 0o644.
    ///
    /// - Parameters:
    ///   - content: The plist XML string to write.
    ///   - url: The destination file URL.
    /// - Throws: ``LaunchdManagerError/plistWriteFailed(_:)`` if the write
    ///   or permission change fails.
    private func writePlistFile(content: String, to url: URL) throws {
        guard let data = content.data(using: .utf8) else {
            throw LaunchdManagerError.plistWriteFailed(
                "Failed to encode plist content as UTF-8."
            )
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw LaunchdManagerError.plistWriteFailed(
                "Failed to write plist to \(url.path): \(error.localizedDescription)"
            )
        }

        // Set standard 644 permissions: owner read/write, group and others read-only.
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
        } catch {
            throw LaunchdManagerError.plistWriteFailed(
                "Failed to set permissions on \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Bootstraps the agent into the current user's GUI domain.
    ///
    /// Runs `launchctl bootstrap gui/<uid> <plistPath>` to load and start
    /// the agent immediately.
    ///
    /// - Parameter plistPath: The absolute path to the plist file.
    /// - Throws: ``LaunchdManagerError/launchctlFailed(_:)`` if the
    ///   bootstrap command exits with a non-zero status.
    private func bootstrapAgent(plistPath: String) throws {
        let domainTarget = "gui/\(currentUID())"
        try runLaunchctl(["bootstrap", domainTarget, plistPath])
    }

    /// Runs `/bin/launchctl` with the given arguments and waits for it to exit.
    ///
    /// Shared by the commands that must succeed (`bootstrap`, `kickstart`).
    /// Standard output is discarded; standard error is captured and folded
    /// into the thrown error so the caller can surface launchd's own message.
    ///
    /// - Parameter arguments: The launchctl subcommand and its operands.
    /// - Throws: ``LaunchdManagerError/launchctlFailed(_:)`` if launchctl
    ///   cannot be started or exits with a non-zero status.
    private func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw LaunchdManagerError.launchctlFailed(
                "Failed to launch launchctl: \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? "Unknown error"
            let command = arguments.first ?? "launchctl"

            throw LaunchdManagerError.launchctlFailed(
                "launchctl \(command) exited with status \(process.terminationStatus): \(errorMessage)"
            )
        }
    }

    /// Queries launchctl to determine if the agent is currently loaded and running.
    ///
    /// Runs `launchctl print gui/<uid>/com.gravitek.calmirror.sync` and parses
    /// the output for a `pid =` line to determine the running state and PID.
    ///
    /// - Returns: A tuple of `(running, pid)` where `running` indicates whether
    ///   the agent is loaded and `pid` is the process ID if available.
    private func queryAgentRunState() -> (running: Bool, pid: Int?) {
        let uid = currentUID()
        let serviceTarget = "gui/\(uid)/\(Self.serviceLabel)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", serviceTarget]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (false, nil)
        }

        process.waitUntilExit()

        // A non-zero exit status means the service is not loaded.
        guard process.terminationStatus == 0 else {
            return (false, nil)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return (true, nil)
        }

        // Parse the output for a "pid = <number>" line to extract the PID.
        // The launchctl print output contains a line like:
        //   pid = 12345
        // If the agent is loaded but not currently running, it shows:
        //   pid = 0
        // or the pid line may be absent.
        let pid = parsePID(from: output)
        let isRunning = pid != nil && pid != 0

        return (isRunning, pid)
    }

    /// Extracts a PID value from `launchctl print` output.
    ///
    /// Searches for a line matching the pattern `pid = <number>` and
    /// returns the parsed integer value.
    ///
    /// - Parameter output: The raw stdout from `launchctl print`.
    /// - Returns: The PID if found and parseable, or `nil` otherwise.
    private func parsePID(from output: String) -> Int? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid = ") {
                let valueString = trimmed.dropFirst("pid = ".count)
                    .trimmingCharacters(in: .whitespaces)
                return Int(valueString)
            }
        }
        return nil
    }
}
