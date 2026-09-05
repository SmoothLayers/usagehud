import AppKit
import Foundation

enum ClaudePolling {
    // api.anthropic.com/api/oauth/usage is an internal endpoint that rate
    // limits frequent pollers with long Retry-After cooldowns, so Claude never
    // polls faster than this regardless of the interval chosen in Settings.
    static let minimumInterval: TimeInterval = 5 * 60
    // Jitter is upward-only: a poll may fire late but never early, so a
    // server-mandated cooldown can never be cut short.
    static let jitterFraction = 0.1

    static func interval(from userInterval: TimeInterval) -> TimeInterval {
        max(userInterval, minimumInterval)
    }

    static func jittered(
        _ delay: TimeInterval,
        random: (ClosedRange<Double>) -> Double = { .random(in: $0) }
    ) -> TimeInterval {
        guard delay > 0 else { return delay }
        return delay + random(0...(delay * jitterFraction))
    }
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

enum ClaudeFreshness {
    static let livePollSuppression: TimeInterval = 5 * 60
    static let liveDedupeInterval: TimeInterval = 30
    static let ordinaryCacheRetention: TimeInterval = 30 * 60
    static let rateLimitedCacheRetention: TimeInterval = 24 * 60 * 60

    static func canRetain(_ usage: ProviderUsage, after error: Error, now: Date) -> Bool {
        let retention: TimeInterval
        if case UsageError.rateLimited = error {
            retention = rateLimitedCacheRetention
        } else {
            retention = ordinaryCacheRetention
        }
        return now.timeIntervalSince(usage.fetchedAt) <= retention
    }
}

enum ClaudeWindowActivationState: Equatable {
    case idle
    case running
    case estimated(Date)
    case confirmed(Date)
    case failed(String)
}

enum KimiFreshness {
    static let cacheRetention: TimeInterval = 30 * 60

    static func canRetain(_ usage: ProviderUsage, now: Date) -> Bool {
        now.timeIntervalSince(usage.fetchedAt) <= cacheRetention
    }

    static func notice(after error: Error) -> String {
        if case UsageError.notLoggedIn = error {
            return "Session expired · showing last result"
        }
        return "Update failed · showing last result"
    }
}

struct PersistedClaudeCooldown: Equatable {
    let retryAt: Date
    let backoffAttempt: Int
}

enum ClaudeCooldownPersistence {
    private static let retryAtKey = "claudeCooldownRetryAt"
    private static let attemptKey = "claudeCooldownBackoffAttempt"

    static func load(from defaults: UserDefaults) -> PersistedClaudeCooldown? {
        guard defaults.object(forKey: retryAtKey) != nil else { return nil }
        let timestamp = defaults.double(forKey: retryAtKey)
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return PersistedClaudeCooldown(
            retryAt: Date(timeIntervalSince1970: timestamp),
            backoffAttempt: max(0, defaults.integer(forKey: attemptKey))
        )
    }

    static func save(_ state: PersistedClaudeCooldown, to defaults: UserDefaults) {
        defaults.set(state.retryAt.timeIntervalSince1970, forKey: retryAtKey)
        defaults.set(state.backoffAttempt, forKey: attemptKey)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: retryAtKey)
        defaults.removeObject(forKey: attemptKey)
    }
}

/// Remembers when each API-backed provider last started a poll so a relaunch
/// resumes the cadence instead of firing a fresh startup burst. Codex is a
/// local CLI call and stays exempt.
enum ProviderPollPersistence {
    static func key(for provider: ProviderKind) -> String {
        switch provider {
        case .codex: return "codexLastPollAttemptAt"
        case .claude: return "claudeLastPollAttemptAt"
        case .kimi: return "kimiLastPollAttemptAt"
        }
    }

    static func lastAttempt(for provider: ProviderKind, from defaults: UserDefaults) -> Date? {
        let timestamp = defaults.double(forKey: key(for: provider))
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func recordAttempt(for provider: ProviderKind, at date: Date, to defaults: UserDefaults) {
        defaults.set(date.timeIntervalSince1970, forKey: key(for: provider))
    }

    /// How long a fresh launch should wait before its first poll: the
    /// remainder of the polling interval measured from the previous run's last
    /// attempt. A future timestamp (clock change) waits the full interval so a
    /// bad clock can never shorten the cadence.
    static func startupDelay(lastAttempt: Date?, interval: TimeInterval, now: Date) -> TimeInterval {
        guard let lastAttempt else { return 0 }
        let elapsed = now.timeIntervalSince(lastAttempt)
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var codex: ProviderState = .loading
    @Published var claude: ProviderState = .loading
    @Published var kimi: ProviderState = .loading
    @Published var isCompact: Bool
    @Published var isRefreshing = false
    @Published var claudeNotice: String?
    @Published var claudeIsStale = false
    @Published var kimiNotice: String?
    @Published var kimiIsStale = false
    @Published var claudeLiveStatus: String?
    @Published private(set) var claudeWindowActivationState: ClaudeWindowActivationState = .idle
    @Published private(set) var claudeWindowScheduleStatus = "Automatic scheduling is off"
    @Published var codexLastSuccess: Date?
    @Published var claudeLastSuccess: Date?
    @Published var kimiLastSuccess: Date?
    @Published var codexNextRefresh: Date?
    @Published var claudeNextRefresh: Date?
    @Published var kimiNextRefresh: Date?
    @Published private(set) var usageAlertsEnabled: Bool

    var compactChanged: ((Bool) -> Void)?
    var usageAlert: ((UsageAlertEvent) -> Void)?
    var usageDisplayChanged: (() -> Void)?

    private let defaults: UserDefaults
    private let settings: AppSettings
    private let alertTracker: UsageAlertTracker
    private let claudeWindowActivator: any ClaudeWindowActivating
    private var codexTimer: Timer?
    private var claudeTimer: Timer?
    private var kimiTimer: Timer?
    private var claudeLiveFreshnessTimer: Timer?
    private var codexIsRefreshing = false
    private var claudeIsRefreshing = false
    private var kimiIsRefreshing = false
    private var hasStarted = false
    @Published private(set) var claudeRateLimitedUntil: Date?
    private var claudeBackoffAttempt = 0
    private var claudeWindowActivationTask: Task<Void, Never>?
    private var claudeWindowActivationAwaitingConfirmation = false
    private var claudeWindowEstimatedResetAt: Date?
    private var claudeWindowScheduleTimer: Timer?
    private var claudeWindowScheduleRetryNotBefore: Date?
    /// True after a poll found Claude Code's credential document without a
    /// login block. Running the CLI cannot fix that, so scheduled window
    /// activations pause until a poll succeeds again.
    private(set) var claudeLoginMissing = false

    init(
        defaults: UserDefaults = .standard,
        settings: AppSettings? = nil,
        claudeWindowActivator: any ClaudeWindowActivating = ClaudeWindowActivator()
    ) {
        self.defaults = defaults
        self.settings = settings ?? AppSettings(defaults: defaults)
        self.claudeWindowActivator = claudeWindowActivator
        alertTracker = UsageAlertTracker(defaults: defaults)
        isCompact = defaults.bool(forKey: "isCompact")
        usageAlertsEnabled = defaults.bool(forKey: "usageAlertsEnabled")
        if let persisted = ClaudeCooldownPersistence.load(from: defaults) {
            claudeRateLimitedUntil = persisted.retryAt
            claudeBackoffAttempt = persisted.backoffAttempt
        }
        if let estimatedResetAt = ClaudeWindowActivationPersistence.load(from: defaults) {
            claudeWindowEstimatedResetAt = estimatedResetAt
            claudeWindowActivationState = .estimated(estimatedResetAt)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        AppLog.info("scheduler", "Independent polling started codex=\(Int(settings.codexPollingInterval))s claude=\(Int(settings.claudePollingInterval))s kimi=\(Int(settings.kimiPollingInterval))s")
        let now = Date.now
        if settings.showCodex {
            refreshCodex(trigger: "startup")
            scheduleCodexTimer()
        }
        if claudeMonitoringEnabled, !restoreClaudeCooldownIfNeeded() {
            let delay = ProviderPollPersistence.startupDelay(
                lastAttempt: ProviderPollPersistence.lastAttempt(for: .claude, from: defaults),
                interval: ClaudePolling.interval(from: settings.claudePollingInterval),
                now: now
            )
            if delay > 0 {
                AppLog.info("scheduler", "Claude startup poll deferred delaySeconds=\(Int(delay.rounded())) source=persisted-interval")
                scheduleClaudeTimer(after: delay, trigger: "startup-deferred", source: "persisted-interval")
            } else {
                refreshClaude(trigger: "startup")
            }
        }
        if settings.showKimi {
            let delay = ProviderPollPersistence.startupDelay(
                lastAttempt: ProviderPollPersistence.lastAttempt(for: .kimi, from: defaults),
                interval: settings.kimiPollingInterval,
                now: now
            )
            if delay > 0 {
                AppLog.info("scheduler", "Kimi startup poll deferred delaySeconds=\(Int(delay.rounded())) source=persisted-interval")
                scheduleDeferredKimiStart(after: delay)
            } else {
                refreshKimi(trigger: "startup")
                scheduleKimiTimer()
            }
        }
        evaluateClaudeWindowSchedule(trigger: "startup")
    }

    func refresh() {
        if settings.showCodex { refreshCodex(trigger: "manual") }
        if settings.showClaude { refreshClaude(trigger: "manual") }
        if settings.showKimi { refreshKimi(trigger: "manual") }
    }

    func refreshStaleProviders(trigger: String, now: Date = .now) {
        guard hasStarted else { return }
        if settings.showCodex,
           codexLastSuccess == nil || now.timeIntervalSince(codexLastSuccess!) >= settings.codexPollingInterval {
            refreshCodex(trigger: trigger)
        }
        if settings.showClaude,
           claudeLastSuccess == nil || now.timeIntervalSince(claudeLastSuccess!) >= ClaudePolling.interval(from: settings.claudePollingInterval) {
            refreshClaude(trigger: trigger)
        }
        if settings.showKimi,
           kimiLastSuccess == nil || now.timeIntervalSince(kimiLastSuccess!) >= settings.kimiPollingInterval {
            refreshKimi(trigger: trigger)
        }
    }

    var canStartClaudeWindow: Bool {
        ClaudeWindowActivationEligibility.canStart(
            resetsAt: claudeWindowEffectiveResetAt,
            isRunning: claudeWindowActivationState == .running,
            isAwaitingConfirmation: claudeWindowActivationAwaitingConfirmation
        )
    }

    var claudeWindowActivationDetail: String {
        switch claudeWindowActivationState {
        case .running:
            return "Sending one restricted background request…"
        case let .estimated(resetAt):
            return "Window started · estimated reset in \(UsageFormatting.resetCountdownValueText(for: resetAt))"
        case let .confirmed(resetAt):
            return "Window started · resets in \(UsageFormatting.resetCountdownValueText(for: resetAt))"
        case let .failed(message):
            return message
        case .idle:
            if let resetAt = claudeWindowEffectiveResetAt, resetAt > .now {
                return "Already active · resets in \(UsageFormatting.resetCountdownValueText(for: resetAt))"
            }
            return "Sends one tool-free request without opening Terminal"
        }
    }

    private var claudeMonitoringEnabled: Bool {
        settings.showClaude || settings.claudeWindowScheduleEnabled
    }

    private var claudeWindowEffectiveResetAt: Date? {
        if let providerResetAt = claude.usage?.primary.resetsAt, providerResetAt > .now {
            return providerResetAt
        }
        if let estimatedResetAt = claudeWindowEstimatedResetAt, estimatedResetAt > .now {
            return estimatedResetAt
        }
        return nil
    }

    func startClaudeWindow(trigger: String = "manual") {
        guard canStartClaudeWindow else {
            AppLog.info("claude-window", "Activation skipped because a window or request is already active")
            return
        }

        claudeWindowActivationTask?.cancel()
        claudeWindowActivationState = .running
        claudeWindowActivationAwaitingConfirmation = false
        AppLog.info("claude-window", "Restricted background activation started trigger=\(trigger)")
        claudeWindowActivationTask = Task {
            do {
                try await claudeWindowActivator.activate()
                guard !Task.isCancelled else { return }
                let estimatedResetAt = Date.now.addingTimeInterval(
                    ClaudeWindowActivationPersistence.windowDuration
                )
                claudeWindowEstimatedResetAt = estimatedResetAt
                ClaudeWindowActivationPersistence.save(estimatedResetAt, to: defaults)
                claudeWindowActivationState = .estimated(estimatedResetAt)
                claudeWindowActivationAwaitingConfirmation = true
                claudeWindowScheduleRetryNotBefore = nil
                AppLog.info("claude-window", "Activation request completed; estimated reset saved and provider confirmation pending")
                evaluateClaudeWindowSchedule(trigger: "activation-succeeded")
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                refreshClaude(trigger: "window-activation", force: true)
            } catch {
                guard !Task.isCancelled else { return }
                claudeWindowActivationState = .failed(error.localizedDescription)
                claudeWindowActivationAwaitingConfirmation = false
                if settings.claudeWindowScheduleEnabled {
                    claudeWindowScheduleRetryNotBefore = Date.now.addingTimeInterval(
                        ClaudeWindowSchedule.failureRetryDelay
                    )
                    evaluateClaudeWindowSchedule(trigger: "activation-failed")
                }
                AppLog.error("claude-window", "Activation failed: \(error.localizedDescription)")
            }
            claudeWindowActivationTask = nil
        }
    }

    func ingestClaudeLive(_ snapshot: ClaudeLiveUsageSnapshot) {
        guard settings.showClaude else { return }
        let previous = claude.usage
        guard let merged = ClaudeLiveUsageParser.mergedUsage(snapshot: snapshot, previous: previous) else {
            AppLog.warning("claude-live", "Ignored live update without a 5h window or cached baseline")
            return
        }
        if let previous,
           previous.source == .liveSession,
           previous.primary == merged.primary,
           previous.secondary == merged.secondary,
           snapshot.receivedAt.timeIntervalSince(previous.fetchedAt) < ClaudeFreshness.liveDedupeInterval {
            return
        }

        claude = .loaded(merged)
        claudeLastSuccess = merged.fetchedAt
        claudeNotice = nil
        claudeIsStale = false
        evaluateAlerts(for: merged)
        scheduleClaudeLiveFreshnessExpiry(for: merged)
        if claudeRateLimitedUntil == nil {
            scheduleClaudeTimer(
                after: ClaudePolling.interval(from: settings.claudePollingInterval),
                trigger: "timer",
                source: "live-session"
            )
        }
        usageDisplayChanged?()
        AppLog.info("claude-live", "Live usage applied remaining=\(Int(merged.primary.remainingPercent.rounded()))%")
        evaluateClaudeWindowSchedule(trigger: "claude-live")
    }

    func applyClaudeWindowScheduleSettings() {
        if settings.claudeWindowScheduleEnabled,
           hasStarted,
           !settings.showClaude,
           claudeTimer == nil,
           !claudeIsRefreshing {
            refreshClaude(trigger: "window-schedule-enabled")
        } else if !settings.claudeWindowScheduleEnabled, !settings.showClaude {
            claudeTimer?.invalidate()
            claudeTimer = nil
            claudeNextRefresh = nil
        }
        evaluateClaudeWindowSchedule(trigger: "settings")
    }

    func handleClaudeWindowScheduleEvent(trigger: String) {
        evaluateClaudeWindowSchedule(trigger: trigger)
    }

    func stopClaudeWindowSchedule() {
        claudeWindowScheduleTimer?.invalidate()
        claudeWindowScheduleTimer = nil
    }

    func state(for provider: ProviderKind) -> ProviderState {
        switch provider {
        case .codex: return codex
        case .claude: return claude
        case .kimi: return kimi
        }
    }

    func isStale(for provider: ProviderKind) -> Bool {
        switch provider {
        case .codex: return false
        case .claude: return claudeIsStale
        case .kimi: return kimiIsStale
        }
    }

    func visualStatus(for provider: ProviderKind, now: Date = .now) -> ProviderVisualStatus {
        ProviderVisualStatus.status(
            state: state(for: provider),
            isStale: isStale(for: provider),
            cooldownUntil: provider == .claude ? claudeRateLimitedUntil : nil,
            now: now
        )
    }

    func notice(for provider: ProviderKind) -> String? {
        switch provider {
        case .codex: return nil
        case .claude: return claudeNotice
        case .kimi: return kimiNotice
        }
    }

    func toggleCompact() {
        isCompact.toggle()
        defaults.set(isCompact, forKey: "isCompact")
        compactChanged?(isCompact)
    }

    func setUsageAlertsEnabled(_ enabled: Bool) {
        guard usageAlertsEnabled != enabled else { return }
        usageAlertsEnabled = enabled
        defaults.set(enabled, forKey: "usageAlertsEnabled")
        if enabled {
            alertTracker.clear()
            primeAlertBaseline(from: codex.usage)
            primeAlertBaseline(from: claude.usage)
            primeAlertBaseline(from: kimi.usage)
        }
        AppLog.info("alerts", "Usage alerts enabled=\(enabled)")
    }

    func applyPollingSettings() {
        guard codexTimer != nil || claudeTimer != nil || kimiTimer != nil
            || codexLastSuccess != nil || claudeLastSuccess != nil || kimiLastSuccess != nil
        else { return }
        if settings.showCodex { scheduleCodexTimer() }
        if claudeMonitoringEnabled, claudeRateLimitedUntil == nil, !claudeIsRefreshing {
            scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "settings")
        }
        if settings.showKimi { scheduleKimiTimer() }
        AppLog.info("scheduler", "Polling interval changed codex=\(Int(settings.codexPollingInterval))s claude=\(Int(settings.claudePollingInterval))s kimi=\(Int(settings.kimiPollingInterval))s")
    }

    func applyProviderSettings() {
        if settings.showCodex {
            let wasInactive = codexTimer == nil
            if wasInactive { scheduleCodexTimer() }
            if wasInactive, !codexIsRefreshing { refreshCodex(trigger: "provider-enabled") }
        } else {
            codexTimer?.invalidate()
            codexTimer = nil
            codexNextRefresh = nil
        }

        if claudeMonitoringEnabled {
            let wasInactive = claudeTimer == nil
            if wasInactive, !claudeIsRefreshing {
                if !restoreClaudeCooldownIfNeeded() {
                    refreshClaude(trigger: "provider-enabled")
                }
            }
        } else {
            claudeTimer?.invalidate()
            claudeTimer = nil
            claudeLiveFreshnessTimer?.invalidate()
            claudeLiveFreshnessTimer = nil
            claudeNextRefresh = nil
        }

        if settings.showKimi {
            let wasInactive = kimiTimer == nil
            if wasInactive { scheduleKimiTimer() }
            if wasInactive, !kimiIsRefreshing { refreshKimi(trigger: "provider-enabled") }
        } else {
            kimiTimer?.invalidate()
            kimiTimer = nil
            kimiNextRefresh = nil
        }
        evaluateClaudeWindowSchedule(trigger: "provider-settings")
        AppLog.info("scheduler", "Provider visibility changed codex=\(settings.showCodex) claude=\(settings.showClaude) kimi=\(settings.showKimi)")
    }

    func applyAlertSettings() {
        alertTracker.clear()
        primeAlertBaseline(from: codex.usage)
        primeAlertBaseline(from: claude.usage)
        primeAlertBaseline(from: kimi.usage)
        AppLog.info("alerts", "Custom alert thresholds changed")
    }

    private func scheduleCodexTimer() {
        codexTimer?.invalidate()
        guard settings.showCodex else { return }
        let interval = settings.codexPollingInterval
        codexNextRefresh = Date.now.addingTimeInterval(interval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.codexNextRefresh = Date.now.addingTimeInterval(self.settings.codexPollingInterval)
                self.updateClaudeCooldownNotice()
                self.refreshCodex(trigger: "timer")
            }
        }
        codexTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshCodex(trigger: String) {
        guard settings.showCodex else {
            AppLog.info("scheduler", "Codex refresh skipped trigger=\(trigger) reason=hidden")
            return
        }
        guard !codexIsRefreshing else {
            AppLog.info("scheduler", "Codex refresh skipped trigger=\(trigger) reason=already-refreshing")
            return
        }

        codexIsRefreshing = true
        updateRefreshingState()
        AppLog.info("scheduler", "Codex refresh started trigger=\(trigger)")
        Task {
            let result = await Self.result(from: CodexUsageProvider())
            switch result {
            case let .success(usage):
                codex = .loaded(usage)
                codexLastSuccess = usage.fetchedAt
                evaluateAlerts(for: usage)
            case let .failure(error):
                AppLog.error("scheduler", "Codex refresh failed: \(error.localizedDescription)")
                codex = .failed(error.localizedDescription)
            }
            codexIsRefreshing = false
            updateRefreshingState()
            usageDisplayChanged?()
            AppLog.info("scheduler", "Codex refresh finished trigger=\(trigger)")
        }
    }

    private func scheduleKimiTimer() {
        kimiTimer?.invalidate()
        guard settings.showKimi else { return }
        let interval = settings.kimiPollingInterval
        kimiNextRefresh = Date.now.addingTimeInterval(interval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.kimiNextRefresh = Date.now.addingTimeInterval(self.settings.kimiPollingInterval)
                self.refreshKimi(trigger: "timer")
            }
        }
        kimiTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// One-shot bridge for a deferred launch: fires the held-back startup poll
    /// and only then hands over to the ordinary repeating timer.
    private func scheduleDeferredKimiStart(after delay: TimeInterval) {
        kimiTimer?.invalidate()
        kimiNextRefresh = Date.now.addingTimeInterval(delay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshKimi(trigger: "startup-deferred")
                self.scheduleKimiTimer()
            }
        }
        kimiTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshKimi(trigger: String) {
        guard settings.showKimi else {
            AppLog.info("scheduler", "Kimi refresh skipped trigger=\(trigger) reason=hidden")
            return
        }
        guard !kimiIsRefreshing else {
            AppLog.info("scheduler", "Kimi refresh skipped trigger=\(trigger) reason=already-refreshing")
            return
        }

        kimiIsRefreshing = true
        ProviderPollPersistence.recordAttempt(for: .kimi, at: .now, to: defaults)
        updateRefreshingState()
        AppLog.info("scheduler", "Kimi refresh started trigger=\(trigger)")
        Task {
            let result = await Self.result(from: KimiUsageProvider())
            switch result {
            case let .success(usage):
                kimi = .loaded(usage)
                kimiLastSuccess = usage.fetchedAt
                kimiNotice = nil
                kimiIsStale = false
                evaluateAlerts(for: usage)
            case let .failure(error):
                retainKimiCacheOrFail(error: error, now: .now)
            }
            kimiIsRefreshing = false
            updateRefreshingState()
            usageDisplayChanged?()
            AppLog.info("scheduler", "Kimi refresh finished trigger=\(trigger)")
        }
    }

    private func retainKimiCacheOrFail(error: Error, now: Date) {
        if let usage = kimi.usage, KimiFreshness.canRetain(usage, now: now) {
            AppLog.error("scheduler", "Kimi refresh failed; retaining bounded cache: \(error.localizedDescription)")
            kimiNotice = KimiFreshness.notice(after: error)
            kimiIsStale = true
        } else {
            AppLog.error("scheduler", "Kimi cached result unavailable: \(error.localizedDescription)")
            kimi = .failed(error.localizedDescription)
            kimiNotice = nil
            kimiIsStale = false
        }
    }

    private func refreshClaude(trigger: String, force: Bool = false) {
        guard claudeMonitoringEnabled else {
            AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=hidden")
            return
        }
        let now = Date.now
        if let retryAt = claudeRateLimitedUntil, now < retryAt {
            let wait = UsageFormatting.durationText(retryAt.timeIntervalSince(now))
            claudeNotice = "Rate limited · retry in \(wait)"
            if claude.usage == nil { claude = .failed("Claude cooling down; retry in \(wait)") }
            AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=cooldown")
            return
        }
        if claudeRateLimitedUntil != nil {
            claudeRateLimitedUntil = nil
            ClaudeCooldownPersistence.clear(from: defaults)
        }

        if !force, let current = claude.usage,
           current.source == .liveSession {
            let age = now.timeIntervalSince(current.fetchedAt)
            if age >= 0, age < ClaudeFreshness.livePollSuppression {
                scheduleClaudeTimer(
                    after: ClaudeFreshness.livePollSuppression - age,
                    trigger: "timer",
                    source: "live-fresh"
                )
                AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=fresh-live-session")
                return
            }
        }

        guard !claudeIsRefreshing else {
            AppLog.info("scheduler", "Claude refresh skipped trigger=\(trigger) reason=already-refreshing")
            return
        }

        // Manual refreshes replace the pending normal timer. A rate-limit timer
        // cannot reach this point until its cooldown has expired.
        claudeTimer?.invalidate()
        claudeTimer = nil
        claudeNextRefresh = nil
        claudeIsRefreshing = true
        ProviderPollPersistence.recordAttempt(for: .claude, at: now, to: defaults)
        updateRefreshingState()
        AppLog.info("scheduler", "Claude refresh started trigger=\(trigger)")
        Task {
            let result = await Self.result(from: ClaudeUsageProvider())
            applyClaudeResult(result, now: .now, attemptStartedAt: now)
            claudeIsRefreshing = false
            updateRefreshingState()
            AppLog.info("scheduler", "Claude refresh finished trigger=\(trigger)")
        }
    }

    private func applyClaudeResult(
        _ result: Result<ProviderUsage, Error>,
        now: Date,
        attemptStartedAt: Date
    ) {
        let newerLiveUsage = claude.usage.map {
            $0.source == .liveSession && $0.fetchedAt > attemptStartedAt
        } ?? false
        switch result {
        case let .success(usage):
            if newerLiveUsage {
                AppLog.info("scheduler", "Claude OAuth result ignored because a newer live update arrived")
                scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "newer-live")
                usageDisplayChanged?()
                evaluateClaudeWindowSchedule(trigger: "oauth-ignored")
                return
            }
            let displayResult = usageApplyingClaudeWindowEstimate(to: usage, now: now)
            let displayedUsage = displayResult.usage
            claude = .loaded(displayedUsage)
            claudeLiveFreshnessTimer?.invalidate()
            claudeLiveFreshnessTimer = nil
            claudeLastSuccess = displayedUsage.fetchedAt
            evaluateAlerts(for: displayedUsage)
            claudeNotice = displayResult.isEstimated
                ? "Reset estimated from successful background request"
                : nil
            claudeIsStale = false
            claudeBackoffAttempt = 0
            claudeRateLimitedUntil = nil
            ClaudeCooldownPersistence.clear(from: defaults)
            scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "normal")
            claudeLoginMissing = false
            confirmClaudeWindowActivation(with: usage, now: now)

        case let .failure(error):
            if case let UsageError.rateLimited(retryAfter) = error {
                let backoff = ClaudeBackoff.decision(retryAfter: retryAfter, attempt: claudeBackoffAttempt)
                let delay = backoff.delay
                let source = backoff.source
                claudeBackoffAttempt += 1
                claudeRateLimitedUntil = now.addingTimeInterval(delay)
                ClaudeCooldownPersistence.save(
                    PersistedClaudeCooldown(
                        retryAt: now.addingTimeInterval(delay),
                        backoffAttempt: claudeBackoffAttempt
                    ),
                    to: defaults
                )
                if !newerLiveUsage {
                    retainClaudeCacheOrFail(
                        error: error,
                        now: now,
                        notice: "Rate limited · retry in \(UsageFormatting.durationText(delay))"
                    )
                }
                scheduleClaudeTimer(after: delay, trigger: "claude-retry", source: source)
                AppLog.warning("scheduler", "Claude cooldown scheduled delaySeconds=\(Int(delay.rounded())) source=\(source) attempt=\(claudeBackoffAttempt)")
            } else if newerLiveUsage {
                AppLog.error("scheduler", "Claude refresh failed after a newer live update; live result retained: \(error.localizedDescription)")
                scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "newer-live-error")
            } else if claude.usage != nil {
                ClaudeCooldownPersistence.clear(from: defaults)
                retainClaudeCacheOrFail(
                    error: error,
                    now: now,
                    notice: "Update failed · showing last result"
                )
                scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "error-retry")
            } else {
                ClaudeCooldownPersistence.clear(from: defaults)
                AppLog.error("scheduler", "Claude refresh failed: \(error.localizedDescription)")
                claude = .failed(error.localizedDescription)
                claudeNotice = nil
                claudeIsStale = false
                scheduleClaudeTimer(after: ClaudePolling.interval(from: settings.claudePollingInterval), trigger: "timer", source: "error-retry")
            }
            claudeLoginMissing = ClaudeCredentials.isSignedOut(error)
            if claudeWindowActivationAwaitingConfirmation {
                claudeWindowActivationAwaitingConfirmation = false
                if let estimatedResetAt = claudeWindowEstimatedResetAt, estimatedResetAt > now {
                    claudeWindowActivationState = .estimated(estimatedResetAt)
                    AppLog.warning("claude-window", "Provider check failed; keeping the successful activation estimate")
                } else {
                    claudeWindowActivationState = .failed("Request sent, but the timer check failed")
                }
            }
        }
        usageDisplayChanged?()
        evaluateClaudeWindowSchedule(trigger: "oauth-result")
    }

    private func confirmClaudeWindowActivation(with usage: ProviderUsage, now: Date) {
        guard claudeWindowActivationAwaitingConfirmation else { return }
        claudeWindowActivationAwaitingConfirmation = false
        if let resetAt = usage.primary.resetsAt, resetAt > now {
            claudeWindowEstimatedResetAt = nil
            ClaudeWindowActivationPersistence.clear(from: defaults)
            claudeWindowActivationState = .confirmed(resetAt)
            AppLog.info("claude-window", "Activation confirmed by a future reset timestamp")
        } else if let estimatedResetAt = claudeWindowEstimatedResetAt, estimatedResetAt > now {
            claudeWindowActivationState = .estimated(estimatedResetAt)
            AppLog.info("claude-window", "Provider omitted reset timestamp; keeping activation estimate")
        } else {
            claudeWindowActivationState = .failed("Request finished, but Claude did not report a new timer")
            AppLog.warning("claude-window", "Activation could not be confirmed from usage data")
        }
    }

    private func usageApplyingClaudeWindowEstimate(
        to usage: ProviderUsage,
        now: Date
    ) -> (usage: ProviderUsage, isEstimated: Bool) {
        if let providerResetAt = usage.primary.resetsAt, providerResetAt > now {
            claudeWindowEstimatedResetAt = nil
            ClaudeWindowActivationPersistence.clear(from: defaults)
            return (usage, false)
        }
        guard let estimatedResetAt = claudeWindowEstimatedResetAt, estimatedResetAt > now else {
            claudeWindowEstimatedResetAt = nil
            ClaudeWindowActivationPersistence.clear(from: defaults)
            return (usage, false)
        }
        return (
            ProviderUsage(
                kind: usage.kind,
                plan: usage.plan,
                primary: UsageWindow(
                    label: usage.primary.label,
                    usedPercent: usage.primary.usedPercent,
                    resetsAt: estimatedResetAt
                ),
                secondary: usage.secondary,
                fetchedAt: usage.fetchedAt,
                source: usage.source
            ),
            true
        )
    }

    private func retainClaudeCacheOrFail(error: Error, now: Date, notice: String) {
        if let usage = claude.usage, ClaudeFreshness.canRetain(usage, after: error, now: now) {
            AppLog.error("scheduler", "Claude refresh failed; retaining bounded cache: \(error.localizedDescription)")
            claudeNotice = notice
            claudeIsStale = true
        } else {
            AppLog.error("scheduler", "Claude cached result expired: \(error.localizedDescription)")
            claude = .failed(error.localizedDescription)
            claudeNotice = nil
            claudeIsStale = false
        }
    }

    private func scheduleClaudeLiveFreshnessExpiry(for usage: ProviderUsage) {
        claudeLiveFreshnessTimer?.invalidate()
        let fetchedAt = usage.fetchedAt
        let delay = max(1, ClaudeFreshness.livePollSuppression - Date.now.timeIntervalSince(fetchedAt))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard
                    let self,
                    let current = self.claude.usage,
                    current.source == .liveSession,
                    current.fetchedAt == fetchedAt,
                    Date.now.timeIntervalSince(current.fetchedAt) >= ClaudeFreshness.livePollSuppression
                else { return }
                self.claudeIsStale = true
                if self.claudeNotice == nil {
                    self.claudeNotice = "Live session paused · checking OAuth"
                }
                self.usageDisplayChanged?()
            }
        }
        claudeLiveFreshnessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleClaudeTimer(after interval: TimeInterval, trigger: String, source: String) {
        claudeTimer?.invalidate()
        guard claudeMonitoringEnabled else {
            claudeTimer = nil
            claudeNextRefresh = nil
            return
        }
        let delay = ClaudePolling.jittered(max(1, interval))
        let fireAt = Date.now.addingTimeInterval(delay)
        claudeNextRefresh = fireAt
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

    private func evaluateClaudeWindowSchedule(trigger: String, now: Date = .now) {
        claudeWindowScheduleTimer?.invalidate()
        claudeWindowScheduleTimer = nil

        guard settings.claudeWindowScheduleEnabled else {
            claudeWindowScheduleStatus = "Automatic scheduling is off"
            return
        }

        let start = settings.claudeWindowStartMinutes
        let end = settings.claudeWindowEndMinutes
        guard ClaudeWindowSchedule.isActive(
            at: now,
            startMinutes: start,
            endMinutes: end
        ) else {
            let nextStart = ClaudeWindowSchedule.nextActiveStart(after: now, startMinutes: start)
            claudeWindowScheduleStatus = "Paused outside active hours · resumes \(Self.scheduleTimeText(nextStart))"
            scheduleClaudeWindowAction(at: nextStart, reason: "active-hours", trigger: trigger, now: now)
            return
        }

        if let resetAt = claudeWindowEffectiveResetAt, resetAt > now {
            let nextAttempt = resetAt.addingTimeInterval(ClaudeWindowSchedule.activationDelay)
            let fireAt: Date
            if ClaudeWindowSchedule.isActive(at: nextAttempt, startMinutes: start, endMinutes: end) {
                fireAt = nextAttempt
                claudeWindowScheduleStatus = "Window active · next start after reset at \(Self.scheduleTimeText(fireAt))"
            } else {
                fireAt = ClaudeWindowSchedule.nextActiveStart(after: nextAttempt, startMinutes: start)
                claudeWindowScheduleStatus = "Window crosses quiet hours · resumes \(Self.scheduleTimeText(fireAt))"
            }
            scheduleClaudeWindowAction(at: fireAt, reason: "window-reset", trigger: trigger, now: now)
            return
        }

        if claudeLoginMissing {
            claudeWindowScheduleStatus = "Paused · Claude Code is signed out, run /login"
            AppLog.info("claude-window", "Schedule paused because Claude Code is signed out trigger=\(trigger)")
            return
        }

        if let retryAt = claudeWindowScheduleRetryNotBefore, retryAt > now {
            claudeWindowScheduleStatus = "Last request failed · retrying at \(Self.scheduleTimeText(retryAt))"
            scheduleClaudeWindowAction(at: retryAt, reason: "failure-retry", trigger: trigger, now: now)
            return
        }

        if claudeWindowActivationState == .running || claudeWindowActivationAwaitingConfirmation {
            claudeWindowScheduleStatus = "Starting the current Claude window…"
            return
        }

        if case .loading = claude, claudeIsRefreshing {
            let retryAt = now.addingTimeInterval(5)
            claudeWindowScheduleStatus = "Checking the current Claude window…"
            scheduleClaudeWindowAction(at: retryAt, reason: "initial-check", trigger: trigger, now: now)
            return
        }

        claudeWindowScheduleStatus = "Active hours · starting a new window"
        AppLog.info("claude-window", "Schedule activation due trigger=\(trigger)")
        startClaudeWindow(trigger: "schedule-\(trigger)")
    }

    private func scheduleClaudeWindowAction(
        at fireAt: Date,
        reason: String,
        trigger: String,
        now: Date
    ) {
        let delay = max(1, fireAt.timeIntervalSince(now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.claudeWindowScheduleTimer = nil
                self.evaluateClaudeWindowSchedule(trigger: "timer-\(reason)")
            }
        }
        claudeWindowScheduleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        AppLog.info(
            "claude-window",
            "Schedule timer set reason=\(reason) trigger=\(trigger) fireAt=\(ISO8601DateFormatter().string(from: fireAt))"
        )
    }

    private static func scheduleTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return formatter.string(from: date)
    }

    private func restoreClaudeCooldownIfNeeded(now: Date = .now) -> Bool {
        guard let retryAt = claudeRateLimitedUntil else { return false }
        let remaining = retryAt.timeIntervalSince(now)
        guard remaining > 0 else {
            claudeRateLimitedUntil = nil
            ClaudeCooldownPersistence.clear(from: defaults)
            return false
        }

        let wait = UsageFormatting.durationText(remaining)
        claudeNotice = "Rate limited · retry in \(wait)"
        claude = .failed("Claude cooling down; retry in \(wait)")
        claudeIsStale = false
        scheduleClaudeTimer(after: remaining, trigger: "claude-retry", source: "persisted-cooldown")
        AppLog.info("scheduler", "Claude persisted cooldown restored remainingSeconds=\(Int(remaining.rounded()))")
        return true
    }

    private func updateClaudeCooldownNotice(now: Date = .now) {
        guard let retryAt = claudeRateLimitedUntil, now < retryAt else { return }
        claudeNotice = "Rate limited · retry in \(UsageFormatting.durationText(retryAt.timeIntervalSince(now)))"
    }

    private func updateRefreshingState() {
        isRefreshing = codexIsRefreshing || claudeIsRefreshing || kimiIsRefreshing
    }

    private func evaluateAlerts(for usage: ProviderUsage) {
        guard usageAlertsEnabled else { return }
        let primaryThreshold = settings.alertThreshold(provider: usage.kind, slot: .primary)
        if let event = alertTracker.observe(
            provider: usage.kind,
            slot: .primary,
            window: usage.primary,
            thresholds: primaryThreshold == 0 ? [] : [Double(primaryThreshold)]
        ) {
            usageAlert?(event)
        }
        if let secondary = usage.secondary,
           let event = alertTracker.observe(
               provider: usage.kind,
               slot: .secondary,
               window: secondary,
               thresholds: {
                   let value = settings.alertThreshold(provider: usage.kind, slot: .secondary)
                   return value == 0 ? [] : [Double(value)]
               }()
           ) {
            usageAlert?(event)
        }
    }

    private func primeAlertBaseline(from usage: ProviderUsage?) {
        guard let usage else { return }
        _ = alertTracker.observe(
            provider: usage.kind,
            slot: .primary,
            window: usage.primary,
            emitEvents: false
        )
        if let secondary = usage.secondary {
            _ = alertTracker.observe(
                provider: usage.kind,
                slot: .secondary,
                window: secondary,
                emitEvents: false
            )
        }
    }

    private static func result<P: UsageProviding>(from provider: P) async -> Result<ProviderUsage, Error> {
        do {
            return .success(try await provider.fetch())
        } catch {
            return .failure(error)
        }
    }
}
