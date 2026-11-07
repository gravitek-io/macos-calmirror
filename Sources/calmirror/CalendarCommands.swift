import ArgumentParser
import CalmMirrorCore
import EventKit
import Foundation
import Darwin

// MARK: - Version Subcommand

extension CalmMirror {

    /// Prints the current version of the CalmMirror CLI.
    ///
    /// Usage:
    /// ```
    /// calmirror version
    /// ```
    struct Version: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Print the current version"
        )

        func run() throws {
            print("calmirror \(CalmMirrorCore.version)")
        }
    }
}

// MARK: - Calendars Subcommand

extension CalmMirror {

    /// Lists all calendars available in Apple Calendar, grouped by account.
    ///
    /// This subcommand helps users discover calendar identifiers needed
    /// for `rules add`. Calendars are grouped by their source account
    /// (iCloud, Google, Exchange, etc.) and annotated with writability.
    ///
    /// Usage:
    /// ```
    /// calmirror calendars          # human-readable table
    /// calmirror calendars --json   # JSON output
    /// ```
    ///
    /// Exit code 4 if calendar access is denied.
    struct Calendars: ParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "List all calendars grouped by account"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        func run() throws {
            requireCalendarAccess()

            let accounts = CalendarService.shared.calendarsByAccount()

            if accounts.isEmpty || accounts.allSatisfy({ $0.calendars.isEmpty }) {
                if json {
                    print("[]")
                } else {
                    print("No calendars found in Apple Calendar.")
                }
                return
            }

            if json {
                printCalendarsJSON(accounts)
            } else {
                printCalendarsHuman(accounts)
            }
        }

        /// Prints calendars in a human-readable format grouped by account.
        ///
        /// Each account is printed as a header, followed by indented lines
        /// showing calendar ID (first 8 chars), title, and writability.
        private func printCalendarsHuman(
            _ accounts: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])]
        ) {
            for (index, group) in accounts.enumerated() {
                if index > 0 { print() }
                print(group.account)
                for entry in group.calendars {
                    let idShort = shortID(entry.calendar.calendarIdentifier)
                    let title = entry.calendar.title
                    let access = entry.writable ? "read/write" : "read-only"
                    print("  \(idShort)  \(title)  \(access)")
                }
            }
        }

        /// Prints calendars as a JSON array of account objects.
        ///
        /// Each account includes its name, type, and nested calendars with
        /// full identifiers, titles, hex colors, and writability flags.
        private func printCalendarsJSON(
            _ accounts: [(account: String, calendars: [(calendar: EKCalendar, writable: Bool)])]
        ) {
            var result: [[String: Any]] = []

            for group in accounts {
                var accountDict: [String: Any] = [
                    "accountName": group.account
                ]

                var calendarsArray: [[String: Any]] = []
                for entry in group.calendars {
                    let cal = entry.calendar
                    var calDict: [String: Any] = [
                        "id": cal.calendarIdentifier,
                        "title": cal.title,
                        "writable": entry.writable
                    ]

                    // Include CGColor as hex if available.
                    if let cgColor = cal.cgColor,
                       let components = cgColor.components,
                       cgColor.numberOfComponents >= 3 {
                        let r = Int(components[0] * 255)
                        let g = Int(components[1] * 255)
                        let b = Int(components[2] * 255)
                        calDict["color"] = String(format: "#%02X%02X%02X", r, g, b)
                    }

                    calendarsArray.append(calDict)
                }
                accountDict["calendars"] = calendarsArray
                result.append(accountDict)
            }

            // Serialize with sorted keys for deterministic output.
            if let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("[]")
            }
        }
    }
}
