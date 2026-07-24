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
        XCTAssertEqual(WindowInteraction.level(alwaysOnTop: true), .statusBar)
        XCTAssertEqual(WindowInteraction.level(alwaysOnTop: false), .normal)
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
        XCTAssertTrue(settings.showCodex)
        XCTAssertTrue(settings.showClaude)
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
        XCTAssertFalse(settings.claudeLiveUsageEnabled)

        settings.setCodexPollingInterval(600)
        settings.setClaudePollingInterval(900)
        settings.setProvider(.claude, visible: false)
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
        settings.setAccent("63C5FF", provider: .codex)
        settings.setClaudeLiveUsageEnabled(true)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.codexPollingInterval, 600)
        XCTAssertEqual(restored.claudePollingInterval, 900)
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
        XCTAssertFalse(restored.alwaysOnTop)
        XCTAssertFalse(restored.automaticUpdateChecks)
        XCTAssertEqual(restored.textScale, 1.15)
        XCTAssertEqual(restored.barThickness, 8)
        XCTAssertEqual(restored.cornerRadius, 24)
        XCTAssertEqual(restored.compactLayout, .horizontal)
        XCTAssertEqual(restored.codexAccentHex, "63C5FF")
        XCTAssertTrue(restored.claudeLiveUsageEnabled)
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

        settings.setCodexPollingInterval(30)
        XCTAssertEqual(settings.codexPollingInterval, 120)
        settings.setClaudePollingInterval(120)
        XCTAssertEqual(settings.claudePollingInterval, 300)
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

    func testProvidersUseIndependentDefaultIntervals() {
        XCTAssertEqual(PollingSchedule.codexInterval, 120)
        XCTAssertEqual(PollingSchedule.claudeInterval, 300)
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

        // A legacy 2-minute choice is below Claude's floor and falls to its
        // default while Codex keeps it.
        defaults.set(120.0, forKey: "pollingInterval")
        let floored = AppSettings(defaults: defaults)
        XCTAssertEqual(floored.codexPollingInterval, 120)
        XCTAssertEqual(floored.claudePollingInterval, 300)

        // Explicit per-provider values win over the legacy key.
        defaults.set(900.0, forKey: "codexPollingInterval")
        defaults.set(900.0, forKey: "claudePollingInterval")
        let explicit = AppSettings(defaults: defaults)
        XCTAssertEqual(explicit.codexPollingInterval, 900)
        XCTAssertEqual(explicit.claudePollingInterval, 900)
    }

    func testFullScreenSpaceDetectionMatchesScreenSizedNormalWindows() {
        let screen = CGSize(width: 1_728, height: 1_117)
        func entry(layer: Int, pid: Int, width: Double, height: Double) -> [String: Any] {
            [
                "kCGWindowLayer": layer,
                "kCGWindowOwnerPID": pid,
                "kCGWindowBounds": ["X": 0.0, "Y": 0.0, "Width": width, "Height": height],
            ]
        }

        XCTAssertTrue(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [entry(layer: 0, pid: 999, width: 1_728, height: 1_117)],
            screenSizes: [screen],
            excludingPID: 1
        ))
        // Fullscreen windows on notched MacBooks stop short of the notch strip.
        XCTAssertTrue(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [entry(layer: 0, pid: 999, width: 1_728, height: 1_079)],
            screenSizes: [screen],
            excludingPID: 1
        ))
        // A window much shorter than the screen is an ordinary window.
        XCTAssertFalse(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [entry(layer: 0, pid: 999, width: 1_728, height: 1_000)],
            screenSizes: [screen],
            excludingPID: 1
        ))
        // The HUD's own windows never count as a full screen app.
        XCTAssertFalse(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [entry(layer: 0, pid: 1, width: 1_728, height: 1_117)],
            screenSizes: [screen],
            excludingPID: 1
        ))
        // Elevated layers (menu bar, Dock) and ordinary windows never match.
        XCTAssertFalse(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [
                entry(layer: 25, pid: 999, width: 1_728, height: 1_117),
                entry(layer: 0, pid: 999, width: 1_200, height: 800),
            ],
            screenSizes: [screen],
            excludingPID: 1
        ))
        XCTAssertFalse(FullScreenSpaceDetection.fullScreenWindowPresent(
            entries: [],
            screenSizes: [screen],
            excludingPID: 1
        ))
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

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: 125, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(label: "x", usedPercent: -4, resetsAt: nil).remainingPercent, 100)
    }

    func testNVMExecutableCanFindSiblingNodeWithAugmentedPath() throws {
        guard let codex = ExecutableLocator.find("codex") else {
            throw XCTSkip("Codex is not installed on this test host")
        }
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
