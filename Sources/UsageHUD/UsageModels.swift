import Foundation

enum ProviderKind: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

struct ProviderUsage: Equatable {
    let kind: ProviderKind
    let plan: String?
    let primary: UsageWindow
    let secondary: UsageWindow?
    let fetchedAt: Date
}

enum ProviderState: Equatable {
    case loading
    case loaded(ProviderUsage)
    case failed(String)

    var usage: ProviderUsage? {
        guard case let .loaded(usage) = self else { return nil }
        return usage
    }
}

enum UsageError: LocalizedError {
    case executableMissing(String)
    case commandFailed(String)
    case invalidResponse(String)
    case notLoggedIn(String)
    case rateLimited(retryAfter: TimeInterval?)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executableMissing(name):
            return "\(name) CLI not found"
        case let .commandFailed(message), let .invalidResponse(message),
             let .notLoggedIn(message), let .requestFailed(message):
            return message
        case let .rateLimited(retryAfter):
            if let retryAfter {
                return "Claude rate limited; retrying in \(UsageFormatting.durationText(retryAfter))"
            }
            return "Claude rate limited; waiting before retry"
        }
    }
}

enum UsageFormatting {
    static func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        return leftoverMinutes == 0 ? "\(hours)h" : "\(hours)h \(leftoverMinutes)m"
    }

    static func resetText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "Reset time unavailable" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Resetting now" }

        let minutes = Int(remaining / 60)
        if minutes < 60 { return "Resets in \(max(1, minutes))m" }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        if hours < 24 { return leftoverMinutes == 0 ? "Resets in \(hours)h" : "Resets in \(hours)h \(leftoverMinutes)m" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "Resets \(formatter.string(from: date))"
    }

    static func resetCountdownText(for date: Date?, now: Date = .now) -> String {
        "RESET \(resetCountdownValueText(for: date, now: now))"
    }

    static func resetCountdownValueText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "—" }
        let total = Int(ceil(date.timeIntervalSince(now)))
        guard total > 0 else { return "NOW" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return String(format: "%dD %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func refreshCountdownValueText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "—" }
        let total = Int(ceil(date.timeIntervalSince(now)))
        guard total > 0 else { return "NOW" }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func refreshCountdownText(for date: Date?, now: Date = .now) -> String {
        "REFRESH \(refreshCountdownValueText(for: date, now: now))"
    }

    static func updatedStatusText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "UPDATED —" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "UPDATED NOW" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "UPDATED \(max(1, minutes))M" }
        let hours = minutes / 60
        if hours < 24 { return "UPDATED \(hours)H" }
        return "UPDATED \(hours / 24)D"
    }

    static func nextStatusText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "NEXT —" }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "NEXT NOW" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "NEXT \(minutes)M" }
        let hours = Int(ceil(Double(minutes) / 60))
        return "NEXT \(hours)H"
    }

    static func timingHelp(lastSuccess: Date?, nextRefresh: Date?, now: Date = .now) -> String {
        "\(updatedStatusText(for: lastSuccess, now: now)) · \(nextStatusText(for: nextRefresh, now: now))"
    }
}

enum MenuBarUsageFormatter {
    static func text(
        codex: ProviderState,
        claude: ProviderState,
        showCodex: Bool,
        showClaude: Bool
    ) -> String {
        var parts: [String] = []
        if showCodex { parts.append("C\(remainingText(for: codex))") }
        if showClaude { parts.append("A\(remainingText(for: claude))") }
        return parts.joined(separator: " · ")
    }

    private static func remainingText(for state: ProviderState) -> String {
        guard let remaining = state.usage?.primary.remainingPercent else { return "—" }
        return "\(Int(remaining.rounded()))"
    }
}
