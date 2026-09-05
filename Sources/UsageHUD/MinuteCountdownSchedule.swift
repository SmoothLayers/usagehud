import Foundation
import SwiftUI

/// Updates rounded-minute labels only when their text can change. Dates are
/// relative to each reset, so a clock-minute tick cannot leave a label late.
struct MinuteCountdownSchedule: TimelineSchedule {
    let resetsAt: [Date?]

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        let dates = resetsAt.compactMap { $0 }.filter { $0.timeIntervalSinceReferenceDate.isFinite }
        return AnySequence(sequence(first: startDate) { current in
            dates.compactMap { reset -> Date? in
                let remaining = reset.timeIntervalSince(current)
                guard remaining > 0 else { return nil }
                let minutes = ceil(remaining / 60)
                let boundary = reset.addingTimeInterval(-60 * (minutes - 1))
                // Avoid a repeated entry if Date rounding places a boundary
                // on the current instant instead of just after it.
                return boundary > current ? boundary : min(reset, current.addingTimeInterval(60))
            }.min()
        })
    }
}
