import Foundation
import XCTest
@testable import UsageHUD

private actor KimiRequestRecorder {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        requests
    }
}

final class UsageHUDTests: XCTestCase {
    func testWindowSizesPersistSeparatelyForExpandedAndCompactModes() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        WindowSizing.save(NSSize(width: 620, height: 410), compact: false, in: defaults)
        WindowSizing.save(NSSize(width: 510, height: 240), compact: true, in: defaults)

        XCTAssertEqual(
            WindowSizing.savedSize(compact: false, visibleProviderCount: 2, in: defaults),
            NSSize(width: 620, height: 410)
        )
        XCTAssertEqual(
            WindowSizing.savedSize(compact: true, visibleProviderCount: 2, in: defaults),
            NSSize(width: 510, height: 240)
        )
    }

    func testResetWindowSizeOnlyClearsTheSelectedMode() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        WindowSizing.save(NSSize(width: 620, height: 410), compact: false, in: defaults)
        WindowSizing.save(NSSize(width: 510, height: 240), compact: true, in: defaults)
        WindowSizing.reset(compact: true, in: defaults)

        XCTAssertEqual(
            WindowSizing.savedSize(compact: false, visibleProviderCount: 2, in: defaults),
            NSSize(width: 620, height: 410)
        )
        XCTAssertNil(WindowSizing.savedSize(compact: true, visibleProviderCount: 2, in: defaults))
    }

    func testWindowSizesClampToModeLimits() {
        XCTAssertEqual(
            WindowSizing.clampedSize(NSSize(width: 100, height: 50), compact: false, visibleProviderCount: 2),
            NSSize(width: 360, height: 240)
        )
        XCTAssertEqual(
            WindowSizing.clampedSize(NSSize(width: 2_000, height: 1_000), compact: true, visibleProviderCount: 2),
            NSSize(width: 760, height: 420)
        )
        XCTAssertEqual(
            WindowSizing.minimumSize(compact: true, visibleProviderCount: 1),
            NSSize(width: 280, height: 88)
        )
        XCTAssertEqual(
            WindowSizing.minimumSize(compact: true, visibleProviderCount: 2, layout: .horizontal),
            NSSize(width: 560, height: 88)
        )
        XCTAssertEqual(
            WindowSizing.defaultSize(compact: false, visibleProviderCount: 3),
            NSSize(width: 630, height: 270)
        )
        XCTAssertEqual(
            WindowSizing.defaultSize(compact: true, visibleProviderCount: 3),
            NSSize(width: 350, height: 244)
        )
        XCTAssertEqual(
            WindowSizing.minimumSize(compact: true, visibleProviderCount: 3, layout: .horizontal),
            NSSize(width: 840, height: 88)
        )
    }

    func testWindowInteractionTracksLockAndAlwaysOnTopSettings() {
        XCTAssertTrue(WindowInteraction.styleMask(locked: false).contains(.borderless))
        XCTAssertFalse(WindowInteraction.styleMask(locked: false).contains(.titled))
        XCTAssertTrue(WindowInteraction.styleMask(locked: false).contains(.resizable))
        XCTAssertFalse(WindowInteraction.styleMask(locked: true).contains(.resizable))
        XCTAssertEqual(WindowInteraction.level(alwaysOnTop: true), .statusBar)
        XCTAssertEqual(WindowInteraction.level(alwaysOnTop: false), WindowInteraction.desktopLevel)
        XCTAssertEqual(
            WindowInteraction.desktopLevel.rawValue,
            Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
        XCTAssertLessThan(WindowInteraction.desktopLevel.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertTrue(WindowInteraction.collectionBehavior(alwaysOnTop: true).contains(.fullScreenAuxiliary))
        XCTAssertFalse(WindowInteraction.collectionBehavior(alwaysOnTop: false).contains(.fullScreenAuxiliary))
    }

    func testAppSettingsPersistAndRestoreSupportedValues() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.codexPollingInterval, 120)
        XCTAssertEqual(settings.claudePollingInterval, 300)
        XCTAssertEqual(settings.kimiPollingInterval, 300)
        XCTAssertTrue(settings.showCodex)
        XCTAssertTrue(settings.showClaude)
        XCTAssertFalse(settings.showKimi)
        XCTAssertEqual(settings.hudOpacity, 1)
        XCTAssertFalse(settings.showMenuBarUsage)
        XCTAssertTrue(settings.showResetCountdown)
        XCTAssertTrue(settings.showRefreshCountdown)
        XCTAssertFalse(settings.lockHUD)
        XCTAssertFalse(settings.clickThrough)
        XCTAssertTrue(settings.alwaysOnTop)
        XCTAssertTrue(settings.automaticUpdateChecks)
        XCTAssertEqual(settings.textScale, 1)
        XCTAssertEqual(settings.barThickness, 4)
        XCTAssertEqual(settings.cornerRadius, 14)
        XCTAssertEqual(settings.compactLayout, .vertical)
        XCTAssertEqual(settings.codexAccentHex, HUDAccentPalette.codexDefault)
        XCTAssertEqual(settings.kimiAccentHex, HUDAccentPalette.kimiDefault)
        XCTAssertFalse(settings.claudeLiveUsageEnabled)
        XCTAssertFalse(settings.claudeWindowScheduleEnabled)
        XCTAssertEqual(settings.claudeWindowStartMinutes, 8 * 60)
        XCTAssertEqual(settings.claudeWindowEndMinutes, 23 * 60)

        settings.setCodexPollingInterval(600)
        settings.setClaudePollingInterval(900)
        settings.setKimiPollingInterval(600)
        settings.setProvider(.claude, visible: false)
        settings.setProvider(.kimi, visible: true)
        settings.setHUDOpacity(0.72)
        settings.setShowMenuBarUsage(true)
        settings.setShowResetCountdown(false)
        settings.setShowRefreshCountdown(false)
        settings.setAlertThreshold(10, provider: .codex, slot: .primary)
        settings.setAlertThreshold(0, provider: .claude, slot: .secondary)
        settings.setLockHUD(true)
        settings.setClickThrough(true)
        settings.setAlwaysOnTop(false)
        settings.setAutomaticUpdateChecks(false)
        settings.setTextScale(1.15)
        settings.setBarThickness(8)
        settings.setCornerRadius(24)
        settings.setCompactLayout(.horizontal)
        settings.setAccent("3FB6FF", provider: .codex)
        settings.setAccent("FFC83D", provider: .kimi)
        settings.setClaudeLiveUsageEnabled(true)
        settings.setClaudeWindowScheduleEnabled(true)
        settings.setClaudeWindowStartMinutes(7 * 60 + 30)
        settings.setClaudeWindowEndMinutes(22 * 60)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.codexPollingInterval, 600)
        XCTAssertEqual(restored.claudePollingInterval, 900)
        XCTAssertEqual(restored.kimiPollingInterval, 600)
        XCTAssertTrue(restored.showCodex)
        XCTAssertFalse(restored.showClaude)
        XCTAssertTrue(restored.showKimi)
        XCTAssertEqual(restored.hudOpacity, 0.72, accuracy: 0.001)
        XCTAssertTrue(restored.showMenuBarUsage)
        XCTAssertFalse(restored.showResetCountdown)
        XCTAssertFalse(restored.showRefreshCountdown)
        XCTAssertEqual(restored.alertThreshold(provider: .codex, slot: .primary), 10)
        XCTAssertEqual(restored.alertThreshold(provider: .claude, slot: .secondary), 0)
        XCTAssertTrue(restored.lockHUD)
        XCTAssertTrue(restored.clickThrough)
        XCTAssertFalse(restored.alwaysOnTop)
        XCTAssertFalse(restored.automaticUpdateChecks)
        XCTAssertEqual(restored.textScale, 1.15)
        XCTAssertEqual(restored.barThickness, 8)
        XCTAssertEqual(restored.cornerRadius, 24)
        XCTAssertEqual(restored.compactLayout, .horizontal)
        XCTAssertEqual(restored.codexAccentHex, "3FB6FF")
        XCTAssertEqual(restored.kimiAccentHex, "FFC83D")
        XCTAssertTrue(restored.claudeLiveUsageEnabled)
        XCTAssertTrue(restored.claudeWindowScheduleEnabled)
        XCTAssertEqual(restored.claudeWindowStartMinutes, 7 * 60 + 30)
        XCTAssertEqual(restored.claudeWindowEndMinutes, 22 * 60)
    }

    func testLegacyAccentHexMigratesToCurrentPalette() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("F59363", forKey: "claudeAccentHex")
        defaults.set("63C5FF", forKey: "codexAccentHex")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.claudeAccentHex, "FF8A4A")
        XCTAssertEqual(settings.codexAccentHex, "3FB6FF")
    }

    func testMenuBarUsageFormattingUsesEnabledProvidersAndUnavailableMarker() {
        let usage = ProviderUsage(
            kind: .codex,
            plan: nil,
            primary: UsageWindow(label: "5h", usedPercent: 28, resetsAt: nil),
            secondary: nil,
            fetchedAt: .now
        )
        XCTAssertEqual(
            MenuBarUsageFormatter.text(
                codex: .loaded(usage),
                claude: .loading,
                showCodex: true,
                showClaude: true
            ),
            "C72 · A—"
        )
        XCTAssertEqual(
            MenuBarUsageFormatter.text(
                codex: .loaded(usage),
                claude: .loading,
                showCodex: false,
                showClaude: true
            ),
            "A—"
        )
        XCTAssertEqual(
            MenuBarUsageFormatter.text(
                codex: .loaded(usage),
                claude: .loading,
                showCodex: true,
                showClaude: false,
                kimi: .loaded(ProviderUsage(
                    kind: .kimi,
                    plan: nil,
                    primary: UsageWindow(label: "5h", usedPercent: 16, resetsAt: nil),
                    secondary: nil,
                    fetchedAt: .now
                )),
                showKimi: true
            ),
            "C72 · K84"
        )
    }

    func testAppSettingsRejectUnsupportedIntervalAndKeepingNoProviders() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setCodexPollingInterval(30)
        XCTAssertEqual(settings.codexPollingInterval, 120)
        settings.setClaudePollingInterval(120)
        XCTAssertEqual(settings.claudePollingInterval, 300)
        settings.setKimiPollingInterval(120)
        XCTAssertEqual(settings.kimiPollingInterval, 300)
        settings.setProvider(.codex, visible: false)
        XCTAssertFalse(settings.showCodex)
        settings.setProvider(.kimi, visible: true)
        settings.setProvider(.claude, visible: false)
        XCTAssertFalse(settings.showClaude)
        settings.setProvider(.kimi, visible: false)
        XCTAssertTrue(settings.showKimi)
    }

    func testUsageAlertEvaluatorIgnoresFirstReadingAndOrdinaryChanges() {
        XCTAssertNil(
            UsageAlertEvaluator.evaluate(
                provider: .codex,
                windowLabel: "7d window",
                previous: nil,
                current: 8
            )
        )
        XCTAssertNil(
            UsageAlertEvaluator.evaluate(
                provider: .codex,
                windowLabel: "7d window",
                previous: 70,
                current: 60
            )
        )
    }

    func testUsageAlertEvaluatorUsesMostUrgentCrossedThreshold() {
        XCTAssertEqual(
            UsageAlertEvaluator.evaluate(
                provider: .claude,
                windowLabel: "5h window",
                previous: 24,
                current: 4
            ),
            .lowUsage(
                provider: .claude,
                windowLabel: "5h window",
                remainingPercent: 4,
                threshold: 5
            )
        )
    }

    func testUsageAlertEvaluatorHonorsCustomAndDisabledThresholds() {
        XCTAssertNotNil(
            UsageAlertEvaluator.evaluate(
                provider: .codex,
                windowLabel: "5h",
                previous: 26,
                current: 24,
                thresholds: [25]
            )
        )
        XCTAssertNil(
            UsageAlertEvaluator.evaluate(
                provider: .codex,
                windowLabel: "5h",
                previous: 26,
                current: 4,
                thresholds: []
            )
        )
    }

    func testUsageAlertEvaluatorDetectsReset() {
        XCTAssertEqual(
            UsageAlertEvaluator.evaluate(
                provider: .codex,
                windowLabel: "7d window",
                previous: 7,
                current: 96
            ),
            .reset(
                provider: .codex,
                windowLabel: "7d window",
                remainingPercent: 96
            )
        )
    }

    func testUsageAlertTrackerPersistsLatestObservationWithoutDuplicates() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tracker = UsageAlertTracker(defaults: defaults)

        let first = UsageWindow(label: "5h window", usedPercent: 75, resetsAt: nil)
        let low = UsageWindow(label: "5h window", usedPercent: 82, resetsAt: nil)
        XCTAssertNil(tracker.observe(provider: .claude, slot: .primary, window: first))
        XCTAssertNotNil(tracker.observe(provider: .claude, slot: .primary, window: low))
        XCTAssertNil(tracker.observe(provider: .claude, slot: .primary, window: low))
    }

    func testClaudeCooldownPersistsAndClears() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = PersistedClaudeCooldown(
            retryAt: Date(timeIntervalSince1970: 1_800_000_000),
            backoffAttempt: 3
        )

        XCTAssertNil(ClaudeCooldownPersistence.load(from: defaults))
        ClaudeCooldownPersistence.save(expected, to: defaults)
        XCTAssertEqual(ClaudeCooldownPersistence.load(from: defaults), expected)
        ClaudeCooldownPersistence.clear(from: defaults)
        XCTAssertNil(ClaudeCooldownPersistence.load(from: defaults))
    }

    func testProviderPollAttemptsPersistPerProvider() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let attempt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNil(ProviderPollPersistence.lastAttempt(for: .claude, from: defaults))
        ProviderPollPersistence.recordAttempt(for: .claude, at: attempt, to: defaults)
        XCTAssertEqual(ProviderPollPersistence.lastAttempt(for: .claude, from: defaults), attempt)
        // Providers keep independent records, so Claude's poll never delays Kimi's.
        XCTAssertNil(ProviderPollPersistence.lastAttempt(for: .kimi, from: defaults))
    }

    func testStartupPollWaitsOutTheRemainderOfThePollingInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // First-ever launch polls immediately.
        XCTAssertEqual(ProviderPollPersistence.startupDelay(lastAttempt: nil, interval: 300, now: now), 0)
        // A relaunch mid-interval waits out the remainder instead of bursting.
        XCTAssertEqual(
            ProviderPollPersistence.startupDelay(lastAttempt: now.addingTimeInterval(-100), interval: 300, now: now),
            200
        )
        // A relaunch after the interval has fully elapsed polls immediately.
        XCTAssertEqual(
            ProviderPollPersistence.startupDelay(lastAttempt: now.addingTimeInterval(-300), interval: 300, now: now),
            0
        )
        // A last attempt in the future (clock change) waits a full interval
        // rather than computing an even longer delay.
        XCTAssertEqual(
            ProviderPollPersistence.startupDelay(lastAttempt: now.addingTimeInterval(600), interval: 300, now: now),
            300
        )
    }

    func testProviderVisualStatusSpeaksOneVocabularyForEverySurface() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = ProviderUsage(
            kind: .claude,
            plan: nil,
            primary: UsageWindow(label: "5h window", usedPercent: 40, resetsAt: nil),
            secondary: nil,
            fetchedAt: now,
            source: .providerAPI
        )
        let liveUsage = ProviderUsage(
            kind: .claude,
            plan: nil,
            primary: usage.primary,
            secondary: nil,
            fetchedAt: now,
            source: .liveSession
        )
        let cooldown = now.addingTimeInterval(600)

        XCTAssertEqual(
            ProviderVisualStatus.status(state: .loading, isStale: false, cooldownUntil: nil, now: now),
            .loading
        )
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .loaded(usage), isStale: false, cooldownUntil: nil, now: now),
            .fresh
        )
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .loaded(liveUsage), isStale: false, cooldownUntil: nil, now: now),
            .live
        )
        // A stale cache outranks its live source: the user must know the data
        // stopped moving.
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .loaded(liveUsage), isStale: true, cooldownUntil: nil, now: now),
            .stale
        )
        // Rate limited with nothing cached counts down instead of erroring…
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .failed("cooling"), isStale: false, cooldownUntil: cooldown, now: now),
            .cooling(until: cooldown)
        )
        // …but an expired cooldown is just a failure again.
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .failed("x"), isStale: false, cooldownUntil: now, now: now),
            .error
        )
        XCTAssertEqual(
            ProviderVisualStatus.status(state: .failed("x"), isStale: false, cooldownUntil: nil, now: now),
            .error
        )
    }

    func testBreathPhaseStaysInUnitRangeAndCycles() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for step in 0..<48 {
            let phase = HUDMotion.breath(start.addingTimeInterval(Double(step) * 0.1))
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThanOrEqual(phase, 1)
        }
        // One full period returns to the same phase, so every indicator in the
        // app breathes in sync no matter when it appeared.
        XCTAssertEqual(
            HUDMotion.breath(start),
            HUDMotion.breath(start.addingTimeInterval(2.4)),
            accuracy: 0.0001
        )
    }

    func testClaudeRotationGraceIsShortRelativeToTheRequestTimeout() {
        // The grace must be long enough for Claude Code's Keychain write to
        // land but short enough that a poll still finishes well inside the
        // scheduler's expectations (each request already has a 10s timeout).
        XCTAssertGreaterThan(ClaudeUsageProvider.rotationGrace, 0)
        XCTAssertLessThanOrEqual(ClaudeUsageProvider.rotationGrace, 5)
    }

    func testUsageTimingFormatting() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(UsageFormatting.updatedStatusText(for: nil, now: now), "UPDATED —")
        XCTAssertEqual(UsageFormatting.updatedStatusText(for: now.addingTimeInterval(-30), now: now), "UPDATED NOW")
        XCTAssertEqual(UsageFormatting.updatedStatusText(for: now.addingTimeInterval(-125), now: now), "UPDATED 2M")
        XCTAssertEqual(UsageFormatting.nextStatusText(for: nil, now: now), "NEXT —")
        XCTAssertEqual(UsageFormatting.nextStatusText(for: now.addingTimeInterval(119), now: now), "NEXT 2M")
        XCTAssertEqual(UsageFormatting.nextStatusText(for: now.addingTimeInterval(-1), now: now), "NEXT NOW")
    }

    func testResetCountdownFormattingIncludesSecondsAndDays() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(UsageFormatting.resetCountdownText(for: nil, now: now), "RESET —")
        XCTAssertEqual(UsageFormatting.resetCountdownText(for: now, now: now), "RESET NOW")
        XCTAssertEqual(
            UsageFormatting.resetCountdownText(for: now.addingTimeInterval(3_661), now: now),
            "RESET 01:01:01"
        )
        XCTAssertEqual(
            UsageFormatting.resetCountdownText(for: now.addingTimeInterval(90_061), now: now),
            "RESET 1D 01:01:01"
        )
    }

    func testRefreshCountdownFormattingIncludesSeconds() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(UsageFormatting.refreshCountdownText(for: nil, now: now), "REFRESH —")
        XCTAssertEqual(UsageFormatting.refreshCountdownText(for: now, now: now), "REFRESH NOW")
        XCTAssertEqual(
            UsageFormatting.refreshCountdownText(for: now.addingTimeInterval(119), now: now),
            "REFRESH 01:59"
        )
        XCTAssertEqual(
            UsageFormatting.refreshCountdownText(for: now.addingTimeInterval(3_661), now: now),
            "REFRESH 01:01:01"
        )
    }

    func testProvidersUseIndependentDefaultIntervals() {
        XCTAssertEqual(PollingSchedule.codexInterval, 120)
        XCTAssertEqual(PollingSchedule.claudeInterval, 300)
        XCTAssertEqual(PollingSchedule.kimiInterval, 300)
    }

    func testLegacySharedPollingIntervalMigratesToPerProviderSettings() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // A legacy choice valid for both providers carries over to both.
        defaults.set(600.0, forKey: "pollingInterval")
        let migrated = AppSettings(defaults: defaults)
        XCTAssertEqual(migrated.codexPollingInterval, 600)
        XCTAssertEqual(migrated.claudePollingInterval, 600)
        XCTAssertEqual(migrated.kimiPollingInterval, 600)

        // A legacy 2-minute choice is below Claude's floor and falls to its
        // default while Codex keeps it.
        defaults.set(120.0, forKey: "pollingInterval")
        let floored = AppSettings(defaults: defaults)
        XCTAssertEqual(floored.codexPollingInterval, 120)
        XCTAssertEqual(floored.claudePollingInterval, 300)
        XCTAssertEqual(floored.kimiPollingInterval, 300)

        // Explicit per-provider values win over the legacy key.
        defaults.set(900.0, forKey: "codexPollingInterval")
        defaults.set(900.0, forKey: "claudePollingInterval")
        defaults.set(600.0, forKey: "kimiPollingInterval")
        let explicit = AppSettings(defaults: defaults)
        XCTAssertEqual(explicit.codexPollingInterval, 900)
        XCTAssertEqual(explicit.claudePollingInterval, 900)
        XCTAssertEqual(explicit.kimiPollingInterval, 600)
    }

    func testClaudePollingEnforcesFiveMinuteFloorAndUpwardJitter() {
        XCTAssertEqual(ClaudePolling.interval(from: 120), 300)
        XCTAssertEqual(ClaudePolling.interval(from: 300), 300)
        XCTAssertEqual(ClaudePolling.interval(from: 900), 900)

        XCTAssertEqual(ClaudePolling.jittered(300, random: { $0.lowerBound }), 300)
        XCTAssertEqual(ClaudePolling.jittered(300, random: { $0.upperBound }), 330)
        XCTAssertEqual(ClaudePolling.jittered(0, random: { $0.upperBound }), 0)

        let jittered = ClaudePolling.jittered(600)
        XCTAssertGreaterThanOrEqual(jittered, 600)
        XCTAssertLessThanOrEqual(jittered, 660)
    }

    func testZeroRetryAfterUsesFiveMinuteFallback() {
        let zero = ClaudeBackoff.decision(retryAfter: 0, attempt: 0)
        XCTAssertEqual(zero.delay, 300)
        XCTAssertEqual(zero.source, "fallback")

        let missingSecondAttempt = ClaudeBackoff.decision(retryAfter: nil, attempt: 1)
        XCTAssertEqual(missingSecondAttempt.delay, 600)
        XCTAssertEqual(missingSecondAttempt.source, "fallback")

        let validHeader = ClaudeBackoff.decision(retryAfter: 125, attempt: 3)
        XCTAssertEqual(validHeader.delay, 125)
        XCTAssertEqual(validHeader.source, "retry-after")
    }

    func testWindowPositionIsClampedToVisibleScreen() {
        let screen = NSRect(x: 0, y: 24, width: 1_000, height: 700)
        let window = NSSize(width: 430, height: 250)

        XCTAssertEqual(
            WindowPlacement.clampedOrigin(NSPoint(x: 900, y: 650), windowSize: window, visibleFrame: screen),
            NSPoint(x: 570, y: 474)
        )
        XCTAssertEqual(
            WindowPlacement.clampedOrigin(NSPoint(x: -200, y: -100), windowSize: window, visibleFrame: screen),
            NSPoint(x: 0, y: 24)
        )
    }

    func testWindowPositionRequiresBothSavedCoordinates() {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(WindowPlacement.savedOrigin(in: defaults))
        defaults.set(120.0, forKey: WindowPlacement.originXKey)
        XCTAssertNil(WindowPlacement.savedOrigin(in: defaults))
        defaults.set(240.0, forKey: WindowPlacement.originYKey)
        XCTAssertEqual(WindowPlacement.savedOrigin(in: defaults), NSPoint(x: 120, y: 240))
    }

    func testClaudeWindowParsing() throws {
        let raw: [String: Any] = [
            "utilization": 37.5,
            "resets_at": "2026-07-15T03:19:59.974472+00:00",
        ]
        let window = try XCTUnwrap(ClaudeUsageProvider.parseWindow(raw, label: "5h window"))
        XCTAssertEqual(window.usedPercent, 37.5)
        XCTAssertEqual(window.remainingPercent, 62.5)
        XCTAssertNotNil(window.resetsAt)
    }

    func testRecursiveCredentialLookup() throws {
        let credential: [String: Any] = [
            "claudeAiOauth": ["accessToken": "local-test-token"],
        ]
        XCTAssertEqual(ClaudeUsageProvider.findString(key: "accessToken", in: credential), "local-test-token")
    }

    func testClaudeCredentialLocationsPreferScopedThenLegacyThenFile() {
        let config = URL(fileURLWithPath: "/Users/test/.claude")
        XCTAssertEqual(
            ClaudeCredentials.scopedServiceName(configDirectory: config),
            "Claude Code-credentials-462977e4"
        )
        XCTAssertEqual(
            ClaudeCredentials.candidateLocations(configDirectory: config),
            [
                .keychain(service: "Claude Code-credentials-462977e4", source: .scopedKeychain),
                .keychain(service: "Claude Code-credentials", source: .legacyKeychain),
                .file(config.appendingPathComponent(".credentials.json")),
            ]
        )
    }

    func testClaudeCredentialParsingKeepsSourceWithoutExposingRawObject() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "local-test-token",
                "subscriptionType": "max",
            ],
        ])
        XCTAssertEqual(
            ClaudeCredentials.parse(data, source: .credentialsFile),
            ClaudeCredential(accessToken: "local-test-token", plan: "Max", source: .credentialsFile)
        )
        XCTAssertNil(ClaudeCredentials.parse(Data("{}".utf8), source: .credentialsFile))
    }

    func testClaudeCredentialParsingIgnoresMcpOAuthTokens() throws {
        // Real keychain layout: an MCP server token set shares key names with
        // the Claude login. Dictionary order is random, so a recursive lookup
        // picked the MCP token about half the time and produced HTTP 401s.
        let data = try JSONSerialization.data(withJSONObject: [
            "mcpOAuth": [
                "magnific|abc": [
                    "accessToken": "mcp-token",
                    "refreshToken": "mcp-refresh",
                    "serverName": "magnific",
                ],
            ],
            "claudeAiOauth": [
                "accessToken": "claude-token",
                "refreshToken": "claude-refresh",
                "subscriptionType": "max",
            ],
        ])
        for _ in 0..<50 {
            XCTAssertEqual(
                ClaudeCredentials.parse(data, source: .legacyKeychain),
                ClaudeCredential(accessToken: "claude-token", plan: "Max", source: .legacyKeychain)
            )
        }

        let mcpOnly = try JSONSerialization.data(withJSONObject: [
            "mcpOAuth": ["magnific|abc": ["accessToken": "mcp-token"]],
        ])
        XCTAssertNil(ClaudeCredentials.parse(mcpOnly, source: .legacyKeychain))
    }

    func testClaudeCredentialParsingAcceptsFlatLegacyLayout() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "accessToken": "flat-token",
            "subscriptionType": "pro",
        ])
        XCTAssertEqual(
            ClaudeCredentials.parse(data, source: .credentialsFile),
            ClaudeCredential(accessToken: "flat-token", plan: "Pro", source: .credentialsFile)
        )
        XCTAssertNil(ClaudeCredentials.parse(Data("[]".utf8), source: .credentialsFile))
    }

    func testClaudeLiveUsageParsesSchemaVariantsAndMilliseconds() throws {
        let payload: [String: Any] = [
            "rate_limits": [
                "five_hour": ["used_percentage": 18.5, "resets_at": 1_784_668_264],
                "seven_day": ["utilization": 42, "resets_at": 1_784_668_264_000],
            ],
            "workspace": ["ignored": true],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let received = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try XCTUnwrap(ClaudeLiveUsageParser.parse(data, receivedAt: received))
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 18.5)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 42)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, snapshot.sevenDay?.resetsAt)
        XCTAssertEqual(snapshot.receivedAt, received)
    }

    func testClaudeLiveUsageRejectsExpiredRateLimitWindows() throws {
        let received = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try JSONSerialization.data(withJSONObject: [
            "rate_limits": [
                "five_hour": [
                    "used_percentage": 0,
                    "resets_at": received.timeIntervalSince1970 - 1,
                ],
                "seven_day": [
                    "used_percentage": 0,
                    "resets_at": received.timeIntervalSince1970 - 60,
                ],
            ],
        ])

        XCTAssertNil(ClaudeLiveUsageParser.parse(data, receivedAt: received))
    }

    func testClaudeLiveUsageMergesPartialWindowsWithCachedUsage() throws {
        let previous = ProviderUsage(
            kind: .claude,
            plan: "Max",
            primary: UsageWindow(label: "5h window", usedPercent: 10, resetsAt: nil),
            secondary: UsageWindow(label: "7d window", usedPercent: 20, resetsAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 100),
            source: .providerAPI
        )
        let snapshot = ClaudeLiveUsageSnapshot(
            fiveHour: UsageWindow(label: "5h window", usedPercent: 30, resetsAt: nil),
            sevenDay: nil,
            receivedAt: Date(timeIntervalSince1970: 200)
        )
        let merged = try XCTUnwrap(ClaudeLiveUsageParser.mergedUsage(snapshot: snapshot, previous: previous))
        XCTAssertEqual(merged.primary.usedPercent, 30)
        XCTAssertEqual(merged.secondary?.usedPercent, 20)
        XCTAssertEqual(merged.plan, "Max")
        XCTAssertEqual(merged.source, .liveSession)
        XCTAssertEqual(merged.fetchedAt, snapshot.receivedAt)
    }

    func testClaudeStatusLineInstallerNeverOverwritesCustomCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("claude")
        let support = root.appendingPathComponent("support")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let settingsURL = config.appendingPathComponent("settings.json")
        let original: [String: Any] = [
            "statusLine": ["type": "command", "command": "/usr/local/bin/my-statusline"],
            "theme": "dark",
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: settingsURL)

        let installer = ClaudeStatusLineInstaller(
            configDirectory: config,
            applicationSupportDirectory: support
        )
        XCTAssertEqual(try installer.install(), .userStatusLinePresent)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        let statusLine = restored?["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "/usr/local/bin/my-statusline")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    func testClaudeStatusLineInstallerChainsCCStatusLineAndRestoresItExactly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("claude")
        let support = root.appendingPathComponent("support")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let settingsURL = config.appendingPathComponent("settings.json")
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": "npx -y ccstatusline@latest",
            "padding": 0,
        ]
        let original: [String: Any] = [
            "statusLine": originalStatusLine,
            "theme": "dark",
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: settingsURL)

        let installer = ClaudeStatusLineInstaller(
            configDirectory: config,
            applicationSupportDirectory: support
        )
        XCTAssertEqual(try installer.install(), .chainedCCStatusLine)

        var settings = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let managed = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        let managedCommand = try XCTUnwrap(managed["command"] as? String)
        XCTAssertTrue(managedCommand.contains(installer.scriptURL.lastPathComponent))
        XCTAssertTrue(managedCommand.contains("npx -y ccstatusline@latest"))
        XCTAssertEqual((managed["padding"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(settings["theme"] as? String, "dark")
        let sidecarAttributes = try FileManager.default.attributesOfItem(atPath: installer.originalStatusLineURL.path)
        XCTAssertEqual((sidecarAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try installer.uninstall()
        settings = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let restored = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(restored["type"] as? String, originalStatusLine["type"] as? String)
        XCTAssertEqual(restored["command"] as? String, originalStatusLine["command"] as? String)
        XCTAssertEqual((restored["padding"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(settings["theme"] as? String, "dark")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.originalStatusLineURL.path))
    }

    func testClaudeStatusLineChainPassesPayloadToOriginalCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("claude")
        let support = root.appendingPathComponent("support")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let settingsURL = config.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: [
            "statusLine": ["type": "command", "command": "printf ccstatusline"],
        ]).write(to: settingsURL)

        let installer = ClaudeStatusLineInstaller(
            configDirectory: config,
            applicationSupportDirectory: support
        )
        XCTAssertEqual(try installer.install(), .chainedCCStatusLine)
        let settings = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        let managedCommand = try XCTUnwrap(statusLine["command"] as? String)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", managedCommand]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"rate_limits":{"five_hour":{"used_percentage":12}}}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
            "ccstatusline"
        )
    }

    func testClaudeStatusLineCommandRecognitionIsNarrow() {
        XCTAssertTrue(ClaudeStatusLineInstaller.isCCStatusLineCommand("npx -y ccstatusline@latest"))
        XCTAssertTrue(ClaudeStatusLineInstaller.isCCStatusLineCommand("printf ccstatusline"))
        XCTAssertFalse(ClaudeStatusLineInstaller.isCCStatusLineCommand("/usr/local/bin/my-statusline"))
        XCTAssertFalse(ClaudeStatusLineInstaller.isCCStatusLineCommand("echo ccstatusline-helper"))
    }

    func testClaudeStatusLineInstallerOwnsOnlyItsManagedEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("claude")
        let support = root.appendingPathComponent("support")
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = ClaudeStatusLineInstaller(
            configDirectory: config,
            applicationSupportDirectory: support
        )

        XCTAssertEqual(try installer.install(), .installed)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.scriptURL.path))
        let syntaxCheck = Process()
        syntaxCheck.executableURL = URL(fileURLWithPath: "/bin/sh")
        syntaxCheck.arguments = ["-n", installer.scriptURL.path]
        try syntaxCheck.run()
        syntaxCheck.waitUntilExit()
        XCTAssertEqual(syntaxCheck.terminationStatus, 0)
        var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any]
        XCTAssertEqual(
            ClaudeStatusLineInstaller.statusLineOwnership(in: try XCTUnwrap(settings)),
            .managed
        )

        try installer.uninstall()
        settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any]
        XCTAssertEqual(
            ClaudeStatusLineInstaller.statusLineOwnership(in: try XCTUnwrap(settings)),
            .empty
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    func testClaudeLiveServerAcceptsOnlyAuthenticatedLoopbackPayloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let endpoint = root.appendingPathComponent("endpoint")
        let server = ClaudeLiveUsageServer(endpointURL: endpoint)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let received = expectation(description: "authenticated live snapshot")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stale endpoint".utf8).write(to: endpoint)
        try server.start { snapshot in
            XCTAssertEqual(snapshot.fiveHour?.usedPercent, 12)
            received.fulfill()
        }

        for _ in 0..<100 where !FileManager.default.fileExists(atPath: endpoint.path) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let descriptor = try String(contentsOf: endpoint, encoding: .utf8)
        let fields = Dictionary(uniqueKeysWithValues: descriptor
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
        let port = try XCTUnwrap(fields["USAGE_HUD_CLAUDE_PORT"])
        let token = try XCTUnwrap(fields["USAGE_HUD_CLAUDE_TOKEN"])
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/claude"))
        let body = try JSONSerialization.data(withJSONObject: [
            "rate_limits": [
                "five_hour": [
                    "used_percentage": 12,
                    "resets_at": Date.now.addingTimeInterval(3_600).timeIntervalSince1970,
                ],
            ],
        ])

        var unauthorized = URLRequest(url: url)
        unauthorized.httpMethod = "POST"
        unauthorized.httpBody = body
        unauthorized.setValue("application/json", forHTTPHeaderField: "Content-Type")
        unauthorized.setValue("wrong-token", forHTTPHeaderField: "X-Usage-HUD-Token")
        let (_, rejectedResponse) = try await URLSession.shared.data(for: unauthorized)
        XCTAssertEqual((rejectedResponse as? HTTPURLResponse)?.statusCode, 401)

        var authorized = unauthorized
        authorized.setValue(token, forHTTPHeaderField: "X-Usage-HUD-Token")
        let (_, acceptedResponse) = try await URLSession.shared.data(for: authorized)
        XCTAssertEqual((acceptedResponse as? HTTPURLResponse)?.statusCode, 204)
        await fulfillment(of: [received], timeout: 2)

        let attributes = try FileManager.default.attributesOfItem(atPath: endpoint.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testClaudeCacheRetentionIsBoundedByFailureType() {
        let now = Date(timeIntervalSince1970: 100_000)
        func usage(age: TimeInterval) -> ProviderUsage {
            ProviderUsage(
                kind: .claude,
                plan: nil,
                primary: UsageWindow(label: "5h", usedPercent: 50, resetsAt: nil),
                secondary: nil,
                fetchedAt: now.addingTimeInterval(-age)
            )
        }
        XCTAssertTrue(ClaudeFreshness.canRetain(usage(age: 1_799), after: UsageError.requestFailed("offline"), now: now))
        XCTAssertFalse(ClaudeFreshness.canRetain(usage(age: 1_801), after: UsageError.requestFailed("offline"), now: now))
        XCTAssertTrue(ClaudeFreshness.canRetain(usage(age: 86_399), after: UsageError.rateLimited(retryAfter: 60), now: now))
        XCTAssertFalse(ClaudeFreshness.canRetain(usage(age: 86_401), after: UsageError.rateLimited(retryAfter: 60), now: now))
    }

    func testKimiCacheRetentionIsBoundedAndExplainsAuthenticationFailures() {
        let now = Date(timeIntervalSince1970: 100_000)
        func usage(age: TimeInterval) -> ProviderUsage {
            ProviderUsage(
                kind: .kimi,
                plan: nil,
                primary: UsageWindow(label: "5h", usedPercent: 50, resetsAt: nil),
                secondary: nil,
                fetchedAt: now.addingTimeInterval(-age)
            )
        }

        XCTAssertTrue(KimiFreshness.canRetain(usage(age: 1_799), now: now))
        XCTAssertFalse(KimiFreshness.canRetain(usage(age: 1_801), now: now))
        XCTAssertEqual(
            KimiFreshness.notice(after: UsageError.notLoggedIn("expired")),
            "Session expired · showing last result"
        )
        XCTAssertEqual(
            KimiFreshness.notice(after: UsageError.requestFailed("offline")),
            "Update failed · showing last result"
        )
    }

    func testMenuBarMarksRetainedClaudeDataAsStale() {
        let usage = ProviderUsage(
            kind: .claude,
            plan: nil,
            primary: UsageWindow(label: "5h", usedPercent: 3, resetsAt: nil),
            secondary: nil,
            fetchedAt: .now
        )
        XCTAssertEqual(
            MenuBarUsageFormatter.text(
                codex: .loading,
                claude: .loaded(usage),
                showCodex: false,
                showClaude: true,
                claudeStale: true
            ),
            "A97!"
        )
    }

    func testMenuBarMarksRetainedKimiDataAsStale() {
        let usage = ProviderUsage(
            kind: .kimi,
            plan: nil,
            primary: UsageWindow(label: "5h", usedPercent: 20, resetsAt: nil),
            secondary: nil,
            fetchedAt: .now
        )
        XCTAssertEqual(
            MenuBarUsageFormatter.text(
                codex: .loading,
                claude: .loading,
                showCodex: false,
                showClaude: false,
                kimi: .loaded(usage),
                showKimi: true,
                kimiStale: true
            ),
            "K80!"
        )
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: 125, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: -4, resetsAt: nil).remainingPercent, 100)
    }

    func testNVMExecutableCanFindSiblingNodeWithAugmentedPath() throws {
        guard let codex = ExecutableLocator.find("codex") else {
            throw XCTSkip("Codex is not installed on this test host")
        }
        let resolved = URL(fileURLWithPath: codex).resolvingSymlinksInPath()
        let head = (try? FileHandle(forReadingFrom: resolved).read(upToCount: 64)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""
        guard head.hasPrefix("#!"), head.contains("node") else {
            throw XCTSkip("Codex is a standalone binary here, not an NVM node launcher")
        }
        let directory = URL(fileURLWithPath: codex).deletingLastPathComponent().path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: "\(directory)/node"))
    }

    func testKimiUsageResponseMapsFiveHourAndWeeklyWindows() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let response: [String: Any] = [
            "usage": [
                "limit": "1000",
                "used": 250,
                "resetTime": "2026-07-27T12:00:00Z",
            ],
            "limits": [
                [
                    "window": ["duration": 1, "timeUnit": "DAY"],
                    "detail": ["limit": 200, "used": 20],
                ],
                [
                    "window": ["duration": 5, "timeUnit": "HOUR"],
                    "detail": [
                        "limit": 100,
                        "remaining": "60",
                        "resetAt": "2026-07-26T18:30:00.000Z",
                    ],
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: response)
        let usage = try KimiUsageProvider.parseUsageData(data, fetchedAt: fetchedAt)
        XCTAssertEqual(usage.kind, .kimi)
        XCTAssertEqual(usage.primary.label, "5h window")
        XCTAssertEqual(usage.primary.usedPercent, 40)
        XCTAssertEqual(usage.primary.remainingPercent, 60)
        XCTAssertEqual(usage.secondary?.label, "7d window")
        XCTAssertEqual(usage.secondary?.usedPercent, 25)
        XCTAssertEqual(usage.fetchedAt, fetchedAt)
    }

    func testKimiUsageResponseRejectsMissingQuotaWindows() {
        let data = Data(#"{"limits":[]}"#.utf8)
        XCTAssertThrowsError(try KimiUsageProvider.parseUsageData(data)) { error in
            guard case UsageError.invalidResponse = error else {
                return XCTFail("Expected an invalid response error, got \(error)")
            }
        }
    }

    func testKimiCredentialsRequireAUsableUnexpiredToken() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let credentialsURL = root.appendingPathComponent("kimi-code.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "access_token": "secret-test-token",
            "expires_at": 1_800_000_100,
        ]).write(to: credentialsURL)

        let credentials = try KimiUsageProvider.readCredentials(from: credentialsURL)
        XCTAssertEqual(credentials.accessToken, "secret-test-token")
        XCTAssertTrue(KimiUsageProvider.isAccessTokenFresh(
            credentials,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        XCTAssertFalse(KimiUsageProvider.isAccessTokenFresh(
            credentials,
            now: Date(timeIntervalSince1970: 1_800_000_096)
        ))
    }

    func testKimiProviderRefreshesExpiredTokenAndPersistsRotatedCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let credentialsURL = root.appendingPathComponent("credentials/kimi-code.json")
        let lockTargetURL = root.appendingPathComponent("oauth/kimi-code")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: credentialsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: [
            "access_token": "expired-access",
            "refresh_token": "old-refresh",
            "expires_at": 1_800_000_000,
            "expires_in": 900,
            "scope": "openid",
            "token_type": "Bearer",
            "preserved_test_field": "keep-me",
        ]).write(to: credentialsURL)

        let recorder = KimiRequestRecorder()
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let provider = KimiUsageProvider(
            credentialsURL: credentialsURL,
            baseURL: URL(string: "https://usage.test/coding/v1")!,
            oauthBaseURL: URL(string: "https://auth.test")!,
            refreshLockTargetURL: lockTargetURL,
            dataForRequest: { request in
                await recorder.append(request)
                let data: Data
                let status: Int
                if request.url?.path == "/api/oauth/token" {
                    status = 200
                    data = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":900,"scope":"openid","token_type":"Bearer"}"#.utf8)
                } else {
                    status = 200
                    data = try JSONSerialization.data(withJSONObject: [
                        "usage": ["limit": 200, "used": 20],
                        "limits": [[
                            "window": ["duration": 5, "timeUnit": "HOUR"],
                            "detail": ["limit": 100, "used": 40],
                        ]],
                    ])
                }
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (data, response)
            },
            now: { now }
        )

        let usage = try await provider.fetch()
        XCTAssertEqual(usage.primary.remainingPercent, 60)

        let requests = await recorder.snapshot()
        XCTAssertEqual(requests.map(\.url?.path), ["/api/oauth/token", "/coding/v1/usages"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        let refreshBody = String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8)
        XCTAssertTrue(refreshBody?.contains("grant_type=refresh_token") == true)
        XCTAssertTrue(refreshBody?.contains("refresh_token=old-refresh") == true)

        let stored = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: credentialsURL)) as? [String: Any]
        )
        XCTAssertEqual(stored["access_token"] as? String, "new-access")
        XCTAssertEqual(stored["refresh_token"] as? String, "new-refresh")
        XCTAssertEqual(stored["expires_at"] as? Double, 1_800_001_000)
        XCTAssertEqual(stored["preserved_test_field"] as? String, "keep-me")
        let attributes = try FileManager.default.attributesOfItem(atPath: credentialsURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockTargetURL.appendingPathExtension("lock").path))
    }

    func testKimiProviderKeepsCredentialsWhenRefreshTokenIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let credentialsURL = root.appendingPathComponent("credentials/kimi-code.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: credentialsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: [
            "access_token": "expired-access",
            "refresh_token": "rejected-refresh",
            "expires_at": 1_800_000_000,
            "expires_in": 900,
        ]).write(to: credentialsURL)

        let provider = KimiUsageProvider(
            credentialsURL: credentialsURL,
            baseURL: URL(string: "https://usage.test/coding/v1")!,
            oauthBaseURL: URL(string: "https://auth.test")!,
            refreshLockTargetURL: root.appendingPathComponent("oauth/kimi-code"),
            dataForRequest: { request in
                let data = Data(#"{"error":"invalid_grant"}"#.utf8)
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (data, response)
            },
            now: { Date(timeIntervalSince1970: 1_800_000_100) }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected the rejected refresh token to require login")
        } catch let UsageError.notLoggedIn(message) {
            XCTAssertTrue(message.contains("run `kimi`"))
        } catch {
            XCTFail("Expected a login error, got \(error)")
        }

        let stored = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: credentialsURL)) as? [String: Any]
        )
        XCTAssertEqual(stored["access_token"] as? String, "expired-access")
        XCTAssertEqual(stored["refresh_token"] as? String, "rejected-refresh")
    }

    func testCodexCurrentRateLimitResponseParsing() throws {
        let response: [String: Any] = [
            "id": 1,
            "result": [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 4,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_784_668_264,
                    ],
                    "secondary": NSNull(),
                    "planType": "prolite",
                ],
            ],
        ]
        let usage = try CodexUsageProvider.parseResponseObject(response)
        XCTAssertEqual(usage.primary.remainingPercent, 96)
        XCTAssertEqual(usage.primary.label, "7d window")
        XCTAssertNil(usage.secondary)
    }

    func testCodexMultiBucketFallback() throws {
        let response: [String: Any] = [
            "id": 1,
            "result": [
                "rateLimits": ["primary": NSNull()],
                "rateLimitsByLimitId": [
                    "codex": [
                        "primary": ["usedPercent": 23, "windowDurationMins": 300],
                        "planType": "plus",
                    ],
                ],
            ],
        ]
        let usage = try CodexUsageProvider.parseResponseObject(response)
        XCTAssertEqual(usage.primary.remainingPercent, 77)
        XCTAssertEqual(usage.primary.label, "5h window")
    }

    func testCodexStatusFallbackParsesLeftAndUsedPercentages() throws {
        let left = try XCTUnwrap(CodexUsageProvider.parseStatusOutput("""
        5h limit: 77% left
        Weekly limit: 91% left
        """))
        XCTAssertEqual(left.primary.usedPercent, 23)
        XCTAssertEqual(left.primary.remainingPercent, 77)
        XCTAssertEqual(left.secondary?.usedPercent, 9)
        XCTAssertEqual(left.source, .cliFallback)

        let used = try XCTUnwrap(CodexUsageProvider.parseStatusOutput("""
        5h limit 23% used
        Weekly limit 9% used
        """))
        XCTAssertEqual(used.primary.usedPercent, 23)
        XCTAssertEqual(used.secondary?.usedPercent, 9)
    }

    func testCodexAuthenticationRPCErrorDoesNotBecomeGenericFailure() {
        XCTAssertThrowsError(try CodexUsageProvider.parseResponseObject([
            "id": 1,
            "error": ["code": -32_600, "message": "codex account authentication required to read rate limits"],
        ])) { error in
            guard case UsageError.notLoggedIn = error else {
                return XCTFail("Expected a sign-in error, got \(error)")
            }
        }
    }

    func testClaudeRetryAfterSeconds() {
        XCTAssertEqual(ClaudeUsageProvider.parseRetryAfter("125"), 125)
        XCTAssertNil(ClaudeUsageProvider.parseRetryAfter("0"))
    }

    func testClaudeWindowActivationUsesRestrictedHeadlessArguments() {
        let arguments = ClaudeWindowActivator.arguments

        XCTAssertTrue(arguments.contains("-p"))
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertTrue(arguments.contains("--disable-slash-commands"))
        XCTAssertTrue(arguments.contains("--no-chrome"))
        XCTAssertTrue(arguments.contains("dontAsk"))
        XCTAssertTrue(arguments.contains("sonnet"))
        XCTAssertTrue(arguments.contains("low"))
        XCTAssertFalse(arguments.contains("--system-prompt"))
        XCTAssertFalse(arguments.contains("--dangerously-skip-permissions"))

        let toolsIndex = try? XCTUnwrap(arguments.firstIndex(of: "--tools"))
        XCTAssertEqual(toolsIndex.map { arguments[$0 + 1] }, "")
        let settingSourcesIndex = try? XCTUnwrap(arguments.firstIndex(of: "--setting-sources"))
        XCTAssertEqual(settingSourcesIndex.map { arguments[$0 + 1] }, "")
    }

    func testClaudeWindowActivationOnlyStartsWithoutAnActiveWindow() {
        let now = Date(timeIntervalSince1970: 1_785_200_000)

        XCTAssertTrue(ClaudeWindowActivationEligibility.canStart(
            resetsAt: nil, isRunning: false, isAwaitingConfirmation: false, now: now
        ))
        XCTAssertTrue(ClaudeWindowActivationEligibility.canStart(
            resetsAt: now.addingTimeInterval(-1), isRunning: false, isAwaitingConfirmation: false, now: now
        ))
        XCTAssertFalse(ClaudeWindowActivationEligibility.canStart(
            resetsAt: now.addingTimeInterval(300), isRunning: false, isAwaitingConfirmation: false, now: now
        ))
        XCTAssertFalse(ClaudeWindowActivationEligibility.canStart(
            resetsAt: nil, isRunning: true, isAwaitingConfirmation: false, now: now
        ))
        XCTAssertFalse(ClaudeWindowActivationEligibility.canStart(
            resetsAt: nil, isRunning: false, isAwaitingConfirmation: true, now: now
        ))
    }

    func testClaudeWindowActivationEstimatePersistsUntilItExpires() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_785_200_000)
        let resetAt = now.addingTimeInterval(ClaudeWindowActivationPersistence.windowDuration)

        ClaudeWindowActivationPersistence.save(resetAt, to: defaults)
        XCTAssertEqual(
            ClaudeWindowActivationPersistence.load(from: defaults, now: now),
            resetAt
        )
        XCTAssertNil(
            ClaudeWindowActivationPersistence.load(
                from: defaults,
                now: resetAt.addingTimeInterval(1)
            )
        )
    }

    func testClaudeWindowScheduleSupportsDaytimeAndOvernightHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 28, hour: 9
        )))
        let lateNight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 28, hour: 23
        )))

        XCTAssertTrue(ClaudeWindowSchedule.isActive(
            at: morning, startMinutes: 8 * 60, endMinutes: 23 * 60, calendar: calendar
        ))
        XCTAssertFalse(ClaudeWindowSchedule.isActive(
            at: lateNight, startMinutes: 8 * 60, endMinutes: 23 * 60, calendar: calendar
        ))
        XCTAssertTrue(ClaudeWindowSchedule.isActive(
            at: lateNight, startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar
        ))
        XCTAssertFalse(ClaudeWindowSchedule.isActive(
            at: morning, startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar
        ))
    }

    func testClaudeWindowScheduleFindsNextActiveStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let lateNight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 28, hour: 23, minute: 30
        )))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 29, hour: 8
        )))

        XCTAssertEqual(
            ClaudeWindowSchedule.nextActiveStart(
                after: lateNight,
                startMinutes: 8 * 60,
                calendar: calendar
            ),
            expected
        )
    }

    func testClaudeRetryAfterHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_784_070_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: now.addingTimeInterval(180))
        XCTAssertEqual(ClaudeUsageProvider.parseRetryAfter(header, now: now), 180)
    }

    func testRetryAfterLogMessagePreservesRawAndParsedValues() {
        XCTAssertEqual(
            ClaudeUsageProvider.retryAfterLogMessage(rawValue: "125", parsedSeconds: 125),
            "Rate limited HTTP 429 Retry-After raw=\"125\" parsedSeconds=125"
        )
        XCTAssertEqual(
            ClaudeUsageProvider.retryAfterLogMessage(rawValue: nil, parsedSeconds: nil),
            "Rate limited HTTP 429 Retry-After raw=\"<missing>\" parsedSeconds=<unparsed>"
        )
    }

    func testAppLoggerWritesAndRotatesLocalLog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = AppLogger(directory: directory, maxBytes: 180)
        XCTAssertTrue(logger.prepare())
        logger.log(.info, category: "test", "first marker")
        logger.log(.warning, category: "test", String(repeating: "x", count: 220))
        logger.flush()

        let current = try String(contentsOf: logger.fileURL, encoding: .utf8)
        let previous = try String(
            contentsOf: directory.appendingPathComponent("usage-hud.previous.log"),
            encoding: .utf8
        )
        XCTAssertTrue(current.contains("[WARN] [test]"))
        XCTAssertTrue(previous.contains("first marker"))
    }

    func testAppLoggerCanClearCurrentAndRotatedLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = AppLogger(directory: directory, maxBytes: 100)
        XCTAssertTrue(logger.prepare())
        logger.log(.info, category: "test", "old log entry")
        logger.log(.warning, category: "test", String(repeating: "x", count: 150))
        logger.flush()
        XCTAssertTrue(logger.clear())

        let current = try String(contentsOf: logger.fileURL, encoding: .utf8)
        XCTAssertTrue(current.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("usage-hud.previous.log").path
            )
        )
    }

    // MARK: - Notch mode

    private var notchedScreenFrame: CGRect { CGRect(x: 0, y: 0, width: 1_512, height: 982) }

    private func hardwareNotch() -> NotchGeometry.Notch {
        NotchGeometry.notch(
            screenFrame: notchedScreenFrame,
            safeAreaTop: 38,
            auxiliaryLeftWidth: 656,
            auxiliaryRightWidth: 656,
            menuBarHeight: 38
        )
    }

    func testNotchIsDerivedFromTheGapBetweenTheAuxiliaryMenuBarAreas() {
        let notch = hardwareNotch()

        XCTAssertTrue(notch.isHardware)
        XCTAssertEqual(notch.rect, CGRect(x: 656, y: 944, width: 200, height: 38))
    }

    func testDisplaysWithoutACameraHousingGetACentredStandIn() {
        let notch = NotchGeometry.notch(
            screenFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 24
        )

        XCTAssertFalse(notch.isHardware)
        XCTAssertEqual(notch.rect, CGRect(x: 860, y: 1_056, width: 200, height: 24))
    }

    func testStandInNotchFallsBackToADefaultMenuBarHeight() {
        let notch = NotchGeometry.notch(
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 0
        )

        XCTAssertEqual(notch.rect.height, NotchGeometry.fallbackMenuBarHeight)
        XCTAssertEqual(notch.rect.maxY, 900)
    }

    func testSecondDisplayNotchIsPlacedInThatDisplaysOwnCoordinates() {
        let notch = NotchGeometry.notch(
            screenFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 24
        )

        XCTAssertEqual(notch.rect.midX, 2_472)
        XCTAssertEqual(notch.rect.maxY, 1_080)
    }

    func testShelfHangsFromTheTopOfTheScreenAndIsCentredOnTheNotch() {
        let notch = hardwareNotch()
        let bounds = NotchGeometry.shelfBounds(notch: notch, providerCount: 3)

        XCTAssertEqual(bounds.maxY, notchedScreenFrame.maxY)
        XCTAssertEqual(bounds.midX, notch.rect.midX)
        XCTAssertEqual(bounds.height, notch.rect.height + NotchGeometry.trayHeight)
    }

    func testExpandedWidthIsTheSameWhateverIsOnShow() {
        let notch = hardwareNotch()
        let widths = (1...3).map { NotchGeometry.expandedWidth(notch: notch, providerCount: $0) }

        // At rest a handful of rings share one width, so toggling providers
        // does not make the tray breathe sideways.
        XCTAssertEqual(Set(widths).count, 1)
        XCTAssertGreaterThanOrEqual(widths[0], NotchGeometry.minimumExpandedWidth)
        XCTAssertGreaterThanOrEqual(widths[0], notch.width)
    }

    func testExpandedWidthGrowsOnceTheRingsWouldNotFit() {
        let notch = hardwareNotch()
        let roomy = NotchGeometry.expandedWidth(notch: notch, providerCount: 8)
        let content = NotchGeometry.trayHorizontalPadding * 2
            + NotchGeometry.tileWidth * 8
            + NotchGeometry.tileSpacing * 7

        XCTAssertEqual(roomy, content)
        XCTAssertGreaterThan(roomy, NotchGeometry.minimumExpandedWidth)
    }

    func testTrayWidthAlreadyFitsTheSwappedInDetailSoHoverNeverResizesIt() {
        let notch = hardwareNotch()

        // Hover swaps content inside one silhouette: whatever the provider
        // count, the open width must already hold the detail layout.
        for count in 1...8 {
            XCTAssertGreaterThanOrEqual(
                NotchGeometry.expandedWidth(notch: notch, providerCount: count),
                NotchGeometry.trayHorizontalPadding * 2 + NotchGeometry.detailTileWidth
            )
        }
        // And the detail leaves usable room for the bars beside the ring.
        XCTAssertGreaterThan(
            NotchGeometry.detailTileWidth - NotchGeometry.tileWidth - NotchGeometry.detailInnerSpacing,
            120
        )
    }

    func testPanelIsSizedForTheTallestStateAndStaysFlushWithTheScreenTop() {
        let notch = hardwareNotch()
        let bounds = NotchGeometry.shelfBounds(notch: notch, providerCount: 3)
        let frame = NotchGeometry.panelFrame(notch: notch, providerCount: 3)

        // Nothing is cast onto the screen edge, so the top gets no padding.
        XCTAssertEqual(frame.maxY, bounds.maxY)
        XCTAssertEqual(frame.maxY, notchedScreenFrame.maxY)
        XCTAssertEqual(frame.midX, bounds.midX)
        // The window never resizes, and the tray never grows past its shelf
        // in any state, so shelf plus shadow room is all it needs.
        XCTAssertGreaterThanOrEqual(frame.height, bounds.height)
        XCTAssertEqual(frame.width, bounds.width + NotchGeometry.shadowPadding * 2)
    }

    func testHotZoneCoversTheNotchAndAShortRunBelowIt() {
        let notch = hardwareNotch()
        let zone = NotchGeometry.hotZone(notch: notch)

        XCTAssertTrue(zone.contains(CGPoint(x: notch.rect.midX, y: notch.rect.midY)))
        // Just under the notch still counts, so a fast downward flick lands.
        XCTAssertTrue(zone.contains(CGPoint(x: notch.rect.midX, y: notch.rect.minY - 1)))
        XCTAssertFalse(zone.contains(CGPoint(x: notch.rect.midX, y: notch.rect.minY - 8)))
        XCTAssertFalse(zone.contains(CGPoint(x: notch.rect.minX - 20, y: notch.rect.midY)))
    }

    func testHotZoneCatchesACursorParkedOnTheVeryTopEdgeOfTheScreen() {
        let notch = hardwareNotch()
        let zone = NotchGeometry.hotZone(notch: notch)

        // Throwing the pointer at the notch parks it on the screen edge, which
        // is the notch's maxY — and CGRect.contains excludes maxY.
        XCTAssertEqual(notch.rect.maxY, notchedScreenFrame.maxY)
        XCTAssertTrue(zone.contains(CGPoint(x: notch.rect.midX, y: notchedScreenFrame.maxY)))
        XCTAssertGreaterThan(zone.maxY, notchedScreenFrame.maxY)
    }

    func testStayZoneForgivesAShakyHandJustOutsideTheTray() {
        let bounds = NotchGeometry.shelfBounds(notch: hardwareNotch(), providerCount: 3)
        let zone = NotchGeometry.stayZone(shelfBounds: bounds)

        XCTAssertTrue(zone.contains(CGPoint(x: bounds.minX - 5, y: bounds.minY - 5)))
        XCTAssertFalse(zone.contains(CGPoint(x: bounds.minX - NotchGeometry.stayZoneSlack - 1, y: bounds.midY)))
        // Downward slack stays tight — nothing opens below the ring row now.
        XCTAssertEqual(zone.height, bounds.height + NotchGeometry.stayZoneSlack * 2)
    }

    func testStayZoneIsSlackOnlyNowThatTheTrayNeverGrows() {
        let bounds = NotchGeometry.shelfBounds(notch: hardwareNotch(), providerCount: 3)
        let zone = NotchGeometry.stayZone(shelfBounds: bounds)

        // Hover swaps content without resizing the shape, so the zone needs
        // no sideways reach beyond forgiveness for a shaky hand.
        XCTAssertTrue(zone.contains(CGPoint(x: bounds.minX - NotchGeometry.stayZoneSlack + 1, y: bounds.midY)))
        XCTAssertTrue(zone.contains(CGPoint(x: bounds.maxX + NotchGeometry.stayZoneSlack - 1, y: bounds.midY)))
        XCTAssertEqual(zone.width, bounds.width + NotchGeometry.stayZoneSlack * 2)
    }

    func testPeekedNotchStaysInsideThePanelWindow() {
        // The peek swells the closed shape; the window never resizes, so the
        // swollen shape (plus its overhang past the housing) has to already
        // fit, or the acknowledgement animation would clip mid-swell.
        let notch = hardwareNotch()
        let frame = NotchGeometry.panelFrame(notch: notch, providerCount: 1)
        let peekedWidth = notch.width
            + NotchGeometry.closedOverhang * 2
            + NotchGeometry.peekWidthGrowth
            + NotchGeometry.closedTopRadius * 2
        let peekedHeight = notch.rect.height + NotchGeometry.peekHeightGrowth

        XCTAssertLessThanOrEqual(peekedWidth, frame.width)
        XCTAssertLessThanOrEqual(peekedHeight, frame.height)
    }

    func testLaunchAtLoginIntentPersistsAcrossLaunches() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Off by default, and setting it survives a fresh AppSettings — the
        // stored intent is what lets the app re-register a login item that
        // macOS silently dropped after a rebuild or move.
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.launchAtLogin)

        settings.setLaunchAtLogin(true)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(AppSettings(defaults: defaults).launchAtLogin)

        settings.setLaunchAtLogin(false)
        XCTAssertFalse(AppSettings(defaults: defaults).launchAtLogin)
    }

    func testNotchModeIsOffUntilItIsTurnedOn() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.notchModeEnabled)

        var changes: [AppSettingsChange] = []
        settings.changed = { changes.append($0) }
        settings.setNotchModeEnabled(true)
        settings.setNotchModeEnabled(true)

        XCTAssertTrue(settings.notchModeEnabled)
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(AppSettings(defaults: defaults).notchModeEnabled)
    }
}
