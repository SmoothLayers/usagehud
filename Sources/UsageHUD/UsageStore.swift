import AppKit
import Foundation

enum PollingSchedule {
    static let codexInterval: TimeInterval = 2 * 60
    static let claudeInterval: TimeInterval = 2 * 60
}

enum ClaudeBackoff {
    static let fallbackIntervals: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    static func decision(retryAfter: TimeInterval?, attempt: Int) -> (delay: TimeInterval, source: String) {
        if let retryAfter, retryAfter.isFinite, retryAfter > 0 {
            return (retryAfter, "retry-after")
        }
        let index = min(max(0, attempt), fallbackIntervals.count - 1)
        return (fallbackIntervals[index], "fallback")
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var codex: ProviderState = .loading
    @Published var claude: ProviderState = .loading
    @Published var isCompact = UserDefaults.standard.bool(forKey: "isCompact")
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false
    @Published var claudeNotice: String?

    var compactChanged: ((Bool) -> Void)?

    private var codexRefreshTask: Task<Void, Never>?
    private var claudeRefreshTask: Task<Void, Never>?
    private var codexTimer: Timer?
    private var claudeTimer: Timer?
    private var codexIsRefreshing = false
    private var claudeIsRefreshing = false
    private var claudeRateLimitedUntil: Date?
    private var claudeBackoffAttempt = 0

    func start() {
        AppLog.info("scheduler", "Independent polling started codexInterval=120s claudeInterval=120s")
        refreshCodex(trigger: "startup")
        refreshClaude(trigger: "startup")
        scheduleCodexTimer()
    }

    func refresh() {
        refreshCodex(trigger: "manual")
        refreshClaude(trigger: "manual")
    }

    func toggleCompact() {
        isCompact.toggle()
        UserDefaults.standard.set(isCompact, forKey: "isCompact")
        compactChanged?(isCompact)
    }

    private func scheduleCodexTimer() {
        codexTimer?.invalidate()
        let timer = Timer(timeInterval: PollingSchedule.codexInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateClaudeCooldownNotice()
                self?.refreshCodex(trigger: "timer")
            }
        }
        codexTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshCodex(trigger: String) {
        guard !codexIsRefreshing else {
            AppLog.info("scheduler", "Codex refresh skipped trigger=\(trigger) reason=already-refreshing")
            return
        }

        codexIsRefreshing = true
        updateRefreshingState()
        AppLog.info("scheduler", "Codex refresh started trigger=\(trigger)")
        codexRefreshTask = Task {
            let result = await Self.result(from: CodexUsageProvider())
            switch result {
            case let .success(usage):
                codex = .loaded(usage)
            case let .failure(error):
                AppLog.error("scheduler", "Codex refresh failed: \(error.localizedDescription)")
                codex = .failed(error.localizedDescription)
            }
            codexIsRefreshing = false
            codexRefreshTask = nil
            lastRefresh = .now
            updateRefreshingState()
            AppLog.info("scheduler", "Codex refresh finished trigger=\(trigger)")
        }
    }

    private func refreshClaude(trigger: String) {
        let now = Date.now
        if let retryAt = claudeRateLimitedUntil, now < retryAt {
            claudeNotice = "Rate limited · retry in \(UsageFormatting.durationText(retryAt.timeIntervalSince(now)))"
            AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=cooldown")
            return
        }
        if claudeRateLimitedUntil != nil { claudeRateLimitedUntil = nil }

        guard !claudeIsRefreshing else {
            AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=already-refreshing")
            return
        }

        // Manual refreshes replace the pending normal timer. A rate-limit timer
        // cannot reach this point until its cooldown has expired.
        claudeTimer?.invalidate()
        claudeTimer = nil
        claudeIsRefreshing = true
        updateRefreshingState()
        AppLog.info("scheduler", "Claude refresh started trigger=\(trigger)")
        claudeRefreshTask = Task {
            let result = await Self.result(from: ClaudeUsageProvider())
            applyClaudeResult(result, now: .now)
            claudeIsRefreshing = false
            claudeRefreshTask = nil
            lastRefresh = .now
            updateRefreshingState()
            AppLog.info("scheduler", "Claude refresh finished trigger=\(trigger)")
        }
    }

    private func applyClaudeResult(_ result: Result<ProviderUsage, Error>, now: Date) {
        switch result {
        case let .success(usage):
            claude = .loaded(usage)
            claudeNotice = nil
            claudeBackoffAttempt = 0
            claudeRateLimitedUntil = nil
            scheduleClaudeTimer(after: PollingSchedule.claudeInterval, trigger: "timer", source: "normal")

        case let .failure(error):
            if case let UsageError.rateLimited(retryAfter) = error {
                let backoff = ClaudeBackoff.decision(retryAfter: retryAfter, attempt: claudeBackoffAttempt)
                let delay = backoff.delay
                let source = backoff.source
                claudeBackoffAttempt += 1
                claudeRateLimitedUntil = now.addingTimeInterval(delay)
                claudeNotice = "Rate limited · retry in \(UsageFormatting.durationText(delay))"
                scheduleClaudeTimer(after: delay, trigger: "claude-retry", source: source)
                AppLog.warning("scheduler", "Claude cooldown scheduled delaySeconds=\(Int(delay.rounded())) source=\(source) attempt=\(claudeBackoffAttempt)")
                if claude.usage == nil { claude = .failed(error.localizedDescription) }
            } else if claude.usage != nil {
                AppLog.error("scheduler", "Claude refresh failed; retaining last result: \(error.localizedDescription)")
                claudeNotice = "Update failed · showing last result"
                scheduleClaudeTimer(after: PollingSchedule.claudeInterval, trigger: "timer", source: "error-retry")
            } else {
                AppLog.error("scheduler", "Claude refresh failed: \(error.localizedDescription)")
                claude = .failed(error.localizedDescription)
                scheduleClaudeTimer(after: PollingSchedule.claudeInterval, trigger: "timer", source: "error-retry")
            }
        }
    }

    private func scheduleClaudeTimer(after interval: TimeInterval, trigger: String, source: String) {
        claudeTimer?.invalidate()
        let delay = max(1, interval)
        let fireAt = Date.now.addingTimeInterval(delay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.claudeTimer = nil
                self.refreshClaude(trigger: trigger)
            }
        }
        claudeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        let fireAtText = ISO8601DateFormatter().string(from: fireAt)
        AppLog.info("scheduler", "Claude timer set delaySeconds=\(Int(delay.rounded())) fireAt=\(fireAtText) source=\(source)")
    }

    private func updateClaudeCooldownNotice(now: Date = .now) {
        guard let retryAt = claudeRateLimitedUntil, now < retryAt else { return }
        claudeNotice = "Rate limited · retry in \(UsageFormatting.durationText(retryAt.timeIntervalSince(now)))"
    }

    private func updateRefreshingState() {
        isRefreshing = codexIsRefreshing || claudeIsRefreshing
    }

    private static func result<P: UsageProviding>(from provider: P) async -> Result<ProviderUsage, Error> {
        do {
            return .success(try await provider.fetch())
        } catch {
            return .failure(error)
        }
    }
}
