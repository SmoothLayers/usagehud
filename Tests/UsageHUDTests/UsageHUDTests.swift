import Foundation
import XCTest
@testable import UsageHUD

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
    }

    func testNativeBorderResizingTracksTheLockSetting() {
        XCTAssertTrue(WindowInteraction.styleMask(locked: false).contains(.borderless))
        XCTAssertFalse(WindowInteraction.styleMask(locked: false).contains(.titled))
        XCTAssertTrue(WindowInteraction.styleMask(locked: false).contains(.resizable))
        XCTAssertFalse(WindowInteraction.styleMask(locked: true).contains(.resizable))
    }

    func testAppSettingsPersistAndRestoreSupportedValues() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.pollingInterval, 120)
        XCTAssertTrue(settings.showCodex)
        XCTAssertTrue(settings.showClaude)
        XCTAssertEqual(settings.hudOpacity, 1)
        XCTAssertFalse(settings.showMenuBarUsage)
        XCTAssertTrue(settings.showResetCountdown)
        XCTAssertTrue(settings.showRefreshCountdown)
        XCTAssertFalse(settings.lockHUD)
        XCTAssertFalse(settings.clickThrough)
        XCTAssertTrue(settings.automaticUpdateChecks)
        XCTAssertEqual(settings.textScale, 1)
        XCTAssertEqual(settings.barThickness, 4)
        XCTAssertEqual(settings.cornerRadius, 14)
        XCTAssertEqual(settings.compactLayout, .vertical)
        XCTAssertEqual(settings.codexAccentHex, HUDAccentPalette.codexDefault)

        settings.setPollingInterval(600)
        settings.setProvider(.claude, visible: false)
        settings.setHUDOpacity(0.72)
        settings.setShowMenuBarUsage(true)
        settings.setShowResetCountdown(false)
        settings.setShowRefreshCountdown(false)
        settings.setAlertThreshold(10, provider: .codex, slot: .primary)
        settings.setAlertThreshold(0, provider: .claude, slot: .secondary)
        settings.setLockHUD(true)
        settings.setClickThrough(true)
        settings.setAutomaticUpdateChecks(false)
        settings.setTextScale(1.15)
        settings.setBarThickness(8)
        settings.setCornerRadius(24)
        settings.setCompactLayout(.horizontal)
        settings.setAccent("63C5FF", provider: .codex)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.pollingInterval, 600)
        XCTAssertTrue(restored.showCodex)
        XCTAssertFalse(restored.showClaude)
        XCTAssertEqual(restored.hudOpacity, 0.72, accuracy: 0.001)
        XCTAssertTrue(restored.showMenuBarUsage)
        XCTAssertFalse(restored.showResetCountdown)
        XCTAssertFalse(restored.showRefreshCountdown)
        XCTAssertEqual(restored.alertThreshold(provider: .codex, slot: .primary), 10)
        XCTAssertEqual(restored.alertThreshold(provider: .claude, slot: .secondary), 0)
        XCTAssertTrue(restored.lockHUD)
        XCTAssertTrue(restored.clickThrough)
        XCTAssertFalse(restored.automaticUpdateChecks)
        XCTAssertEqual(restored.textScale, 1.15)
        XCTAssertEqual(restored.barThickness, 8)
        XCTAssertEqual(restored.cornerRadius, 24)
        XCTAssertEqual(restored.compactLayout, .horizontal)
        XCTAssertEqual(restored.codexAccentHex, "63C5FF")
    }

    func testSemanticVersionComparisonAndReleaseDecoding() throws {
        XCTAssertTrue(SemanticVersion.isNewer("v0.2.10", than: "0.2.9"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0.0", than: "0.9.99"))
        XCTAssertFalse(SemanticVersion.isNewer("v0.2.1", than: "0.2.1"))
        XCTAssertFalse(SemanticVersion.isNewer("0.2.0", than: "0.2.1"))

        let data = #"{"tag_name":"v0.3.0","html_url":"https://github.com/SmoothLayers/usagehud/releases/tag/v0.3.0"}"#.data(using: .utf8)!
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        XCTAssertEqual(release.version, "v0.3.0")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/SmoothLayers/usagehud/releases/tag/v0.3.0")
    }

    func testAutomaticUpdateScheduleRunsAtMostDaily() {
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertTrue(UpdateCheckSchedule.shouldRun(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckSchedule.shouldRun(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(UpdateCheckSchedule.shouldRun(lastCheck: now.addingTimeInterval(-86_400), now: now))
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
    }

    func testAppSettingsRejectUnsupportedIntervalAndKeepingNoProviders() throws {
        let suiteName = "UsageHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setPollingInterval(30)
        XCTAssertEqual(settings.pollingInterval, 120)
        settings.setProvider(.codex, visible: false)
        XCTAssertFalse(settings.showCodex)
        settings.setProvider(.claude, visible: false)
        XCTAssertTrue(settings.showClaude)
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

    func testProvidersUseIndependentTwoMinuteIntervals() {
        XCTAssertEqual(PollingSchedule.codexInterval, 120)
        XCTAssertEqual(PollingSchedule.claudeInterval, 120)
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

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: 125, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: -4, resetsAt: nil).remainingPercent, 100)
    }

    func testNVMExecutableCanFindSiblingNodeWithAugmentedPath() throws {
        let codex = try XCTUnwrap(ExecutableLocator.find("codex"))
        let directory = URL(fileURLWithPath: codex).deletingLastPathComponent().path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: "\(directory)/node"))
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

    func testClaudeRetryAfterSeconds() {
        XCTAssertEqual(ClaudeUsageProvider.parseRetryAfter("125"), 125)
        XCTAssertNil(ClaudeUsageProvider.parseRetryAfter("0"))
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
}
