import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

// MARK: - Root Command

/// Root command for the CalmMirror CLI.
///
/// `CalmMirror` acts as the top-level entry point that dispatches to
/// subcommands. Run `calmirror --help` for usage information.
@main
struct CalmMirror: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "calmirror",
        abstract: "Calendar event mirroring tool for macOS",
        subcommands: [
            Version.self,
            Calendars.self,
            Rules.self,
            Sync.self,
            Logs.self,
            Status.self,
            Agent.self
        ]
    )
}
