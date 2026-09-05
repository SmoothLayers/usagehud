import SwiftUI
import XCTest
@testable import UsageHUD

final class MinuteCountdownScheduleTests: XCTestCase {
    func testUpdatesAtResetRelativeBoundariesAndStopsAtExpiry() {
        let start = Date(timeIntervalSince1970: 1_800_000_017.25)
        let reset = start.addingTimeInterval(125.5)
        let schedule = MinuteCountdownSchedule(resetsAt: [reset])
        XCTAssertEqual(Array(schedule.entries(from: start, mode: .normal)), [
            start, start.addingTimeInterval(5.5), start.addingTimeInterval(65.5), reset,
        ])
    }

    func testExactMinuteDoesNotRepeatTheStartingEntry() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = MinuteCountdownSchedule(resetsAt: [start.addingTimeInterval(120)])
        XCTAssertEqual(Array(schedule.entries(from: start, mode: .normal)), [
            start, start.addingTimeInterval(60), start.addingTimeInterval(120),
        ])
    }

    func testMissingAndExpiredDatesDoNotKeepTicking() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for dates: [Date?] in [[], [nil], [start], [start.addingTimeInterval(-1), nil]] {
            let schedule = MinuteCountdownSchedule(resetsAt: dates)
            XCTAssertEqual(Array(schedule.entries(from: start, mode: .normal)), [start])
        }
    }

    func testTwoWindowsStayAccurateBetweenUpdatesAndAcrossHourRollover() {
        let start = Date(timeIntervalSince1970: 1_800_000_017.25)
        let dates = [start.addingTimeInterval(3_605.5), start.addingTimeInterval(125.25)]
        let entries = Array(MinuteCountdownSchedule(resetsAt: dates).entries(from: start, mode: .normal))
        var index = 0
        // At every quarter-second, the last scheduled text must equal what
        // the old continuously updating formatter would display right now.
        for offset in stride(from: 0.0, through: 3_610, by: 0.25) {
            let now = start.addingTimeInterval(offset)
            while index + 1 < entries.count, entries[index + 1] <= now { index += 1 }
            for reset in dates {
                XCTAssertEqual(
                    NotchThemeStyle.resetText(reset, now: entries[index]),
                    NotchThemeStyle.resetText(reset, now: now)
                )
            }
        }
        XCTAssertEqual(Set(entries).count, entries.count)
        XCTAssertEqual(entries.last, dates.max())
    }

    func testScheduleResumesAtCurrentTimeWithoutReplayingOldTicks() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(125)
        let resumed = start.addingTimeInterval(70)
        let schedule = MinuteCountdownSchedule(resetsAt: [reset])
        XCTAssertEqual(Array(schedule.entries(from: resumed, mode: .lowFrequency)), [resumed, reset])
    }
}
