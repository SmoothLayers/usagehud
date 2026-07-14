import Foundation
import XCTest
@testable import UsageHUD

final class UsageHUDTests: XCTestCase {
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
}
