// RelativeTimeText.swift
// CalMirror — macOS Application
//
// Displays how long ago a date was, in English, and keeps the text current.
//
// Requirements: macOS 26+, Swift 6.2+

import SwiftUI

/// Renders a date as "3 minutes ago" and refreshes itself periodically.
///
/// SwiftUI's `Text(date, style: .relative)` follows the system locale, which
/// produced mixed-language output ("11 min et 20 s ago") in an app whose
/// interface is English only. This view formats with a fixed English locale
/// and coarse units, and re-renders every few seconds so the value never
/// goes stale while the window stays open.
struct RelativeTimeText: View {

    /// The reference date, expected to be in the past.
    let date: Date

    /// Fixed-locale formatter so the wording matches the rest of the UI.
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// Below this age the text reads "just now" instead of counting seconds.
    private static let justNowThreshold: TimeInterval = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            Text(Self.string(for: date, now: context.date))
        }
    }

    /// Formats the age of `date` relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The past date to describe.
    ///   - now: The current time, provided by the timeline.
    /// - Returns: "just now" for very recent dates, otherwise "N units ago".
    static func string(for date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < justNowThreshold {
            return "just now"
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
