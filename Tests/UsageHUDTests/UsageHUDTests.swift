import Foundation
import XCTest
@testable import UsageHUD

final class UsageHUDTests: XCTestCase {
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
