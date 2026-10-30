import Foundation

/// How a recurring item repeats. One-off to-dos have no recurrence.
enum Recurrence: Hashable, Codable, Sendable {
    case daily
    /// Fixed cadence counted from the item's start day.
    case everyNDays(Int)
    /// On the chosen weekdays (`Calendar` numbering: 1 = Sunday … 7 = Saturday).
    case weekly(Set<Int>)
    case monthly(MonthlyRule)
    /// Flexible: done on any N distinct days of the week meets the target.
    case timesPerWeek(Int)
    /// Floating: next due N days after the last completion.
    case daysAfterLastDone(Int)
}

struct MonthlyRule: Hashable, Codable, Sendable {
    enum Anchor: Hashable, Codable, Sendable {
        /// A fixed day of the month; short months clamp to their last day.
        case day(Int)
        case lastDay
    }

    var anchor: Anchor
    /// 1 = monthly, 3 = quarterly, … counted from the start day's month.
    var everyMonths: Int = 1

    func matches(_ day: LocalDay, start: LocalDay) -> Bool {
        let monthsSinceStart = day.monthIndex - start.monthIndex
        guard monthsSinceStart >= 0, monthsSinceStart % max(1, everyMonths) == 0 else { return false }
        switch anchor {
        case let .day(target):
            return day.day == min(max(1, target), day.daysInMonth)
        case .lastDay:
            return day.day == day.daysInMonth
        }
    }
}
