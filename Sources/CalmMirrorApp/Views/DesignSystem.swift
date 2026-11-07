import SwiftUI

struct StatusPill: View {
    let title: String
    var symbol: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.09), in: Capsule())
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalendarEndpoint: View {
    let title: String
    let account: String
    var color: Color = .accentColor
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(account).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title) · \(account)")
    }
}

struct RuleCard<Actions: View, Status: View>: View {
    let title: String
    let sourceName: String
    let sourceAccount: String
    let sourceColor: Color
    let targetName: String
    let targetAccount: String
    let targetColor: Color
    let days: Int
    let isEnabled: Bool
    let isPrivate: Bool
    let allowsChaining: Bool
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var status: () -> Status

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if !isEnabled { StatusPill(title: "Paused", symbol: "pause.fill") }
                Spacer(minLength: 8)
                actions()
            }
            HStack(spacing: 16) {
                CalendarEndpoint(title: sourceName, account: sourceAccount, color: sourceColor)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Copies to")
                CalendarEndpoint(title: targetName, account: targetAccount, color: targetColor)
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 6) {
                StatusPill(title: "\(days) days", symbol: "calendar")
                StatusPill(title: isPrivate ? "Busy only" : "Event titles",
                           symbol: isPrivate ? "lock" : "text.alignleft")
                if allowsChaining {
                    StatusPill(title: "Chaining on", symbol: "link", color: .orange)
                } else {
                    StatusPill(title: "Original events", symbol: "arrow.right")
                }
                Spacer(minLength: 0)
            }
            status().font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.07)))
    }
}
