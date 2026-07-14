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
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executableMissing(name):
            return "\(name) CLI not found"
        case let .commandFailed(message), let .invalidResponse(message),
             let .notLoggedIn(message), let .requestFailed(message):
            return message
        }
    }
}

enum UsageFormatting {
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
}
