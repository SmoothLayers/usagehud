import Foundation

protocol ClaudeWindowActivating {
    func activate() async throws
}

enum ClaudeWindowActivationError: LocalizedError, Equatable {
    case timedOut
    case commandFailed(Int32, detail: String?)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Claude did not respond within 30 seconds"
        case let .commandFailed(status, detail):
            if let detail, !detail.isEmpty {
                return "Claude window request failed (exit \(status)): \(detail)"
            }
            return "Claude window request failed (exit \(status))"
        }
    }

    /// First meaningful line of the CLI's stderr, trimmed and capped, so a
    /// failure such as an expired login is named in the app log.
    static func detail(fromStderr data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let clean = text.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        guard let line = clean
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        return String(line.prefix(200))
    }
}

enum ClaudeWindowActivationEligibility {
    static func canStart(
        resetsAt: Date?,
        isRunning: Bool,
        isAwaitingConfirmation: Bool,
        now: Date = .now
    ) -> Bool {
        guard !isRunning, !isAwaitingConfirmation else { return false }
        guard let resetsAt else { return true }
        return resetsAt <= now
    }
}

enum ClaudeWindowActivationPersistence {
    static let windowDuration: TimeInterval = 5 * 60 * 60
    private static let estimatedResetKey = "claudeWindowEstimatedResetAt"

    static func load(from defaults: UserDefaults, now: Date = .now) -> Date? {
        guard defaults.object(forKey: estimatedResetKey) != nil else { return nil }
        let timestamp = defaults.double(forKey: estimatedResetKey)
        let resetAt = Date(timeIntervalSince1970: timestamp)
        guard timestamp.isFinite, resetAt > now else {
            clear(from: defaults)
            return nil
        }
        return resetAt
    }

    static func save(_ resetAt: Date, to defaults: UserDefaults) {
        defaults.set(resetAt.timeIntervalSince1970, forKey: estimatedResetKey)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: estimatedResetKey)
    }
}

enum ClaudeWindowSchedule {
    static let activationDelay: TimeInterval = 60
    static let failureRetryDelay: TimeInterval = 10 * 60

    static func isActive(
        at date: Date,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar = .current
    ) -> Bool {
        let minute = minuteOfDay(for: date, calendar: calendar)
        if startMinutes == endMinutes { return true }
        if startMinutes < endMinutes {
            return minute >= startMinutes && minute < endMinutes
        }
        return minute >= startMinutes || minute < endMinutes
    }

    static func nextActiveStart(
        after date: Date,
        startMinutes: Int,
        calendar: Calendar = .current
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        for offset in 0...2 {
            guard
                let candidateDay = calendar.date(byAdding: .day, value: offset, to: day),
                let candidate = calendar.date(
                    byAdding: .minute,
                    value: startMinutes,
                    to: candidateDay
                )
            else { continue }
            if candidate > date { return candidate }
        }
        return date.addingTimeInterval(24 * 60 * 60)
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

struct ClaudeWindowActivator: ClaudeWindowActivating {
    static let timeout: TimeInterval = 30
    static let arguments = [
        "-p",
        "--no-session-persistence",
        "--setting-sources", "",
        "--strict-mcp-config",
        "--tools", "",
        "--disable-slash-commands",
        "--no-chrome",
        "--permission-mode", "dontAsk",
        "--model", "sonnet",
        "--effort", "low",
        "--max-turns", "1",
        "--output-format", "text",
        "Reply exactly OK.",
    ]

    func activate() async throws {
        guard let binary = ExecutableLocator.find("claude") else {
            throw UsageError.executableMissing("Claude")
        }

        try await Task.detached(priority: .utility) {
            try Self.run(binary: binary)
        }.value
    }

    private static func run(binary: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        var environment = ProcessInfo.processInfo.environment
        let binaryDirectory = URL(fileURLWithPath: binary).deletingLastPathComponent().path
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let pathParts = inheritedPath.split(separator: ":").map(String.init)
        environment["PATH"] = pathParts.contains(binaryDirectory)
            ? inheritedPath
            : "\(binaryDirectory):\(inheritedPath)"
        environment["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        environment["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        environment["DISABLE_AUTOUPDATER"] = "1"
        process.environment = environment

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Drain stderr off-thread so a chatty CLI cannot fill the pipe and
        // stall before it exits.
        let stderrBox = StderrBox()
        let stderrDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            stderrBox.data = errors.fileHandleForReading.readDataToEndOfFile()
            stderrDrained.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            _ = finished.wait(timeout: .now() + 2)
            throw ClaudeWindowActivationError.timedOut
        }
        _ = stderrDrained.wait(timeout: .now() + 2)

        guard process.terminationStatus == 0 else {
            throw ClaudeWindowActivationError.commandFailed(
                process.terminationStatus,
                detail: ClaudeWindowActivationError.detail(fromStderr: stderrBox.data)
            )
        }
    }
}

private final class StderrBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}
