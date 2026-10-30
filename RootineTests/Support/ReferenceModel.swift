import Foundation

/// A deliberately naive model of which items are listed on a day, for checking `DayPlanner` against
/// (TESTING.md §4.1).
///
/// It does its calendar work with Foundation's `Calendar` instead of `LocalDay`'s ordinal arithmetic, and
/// recomputes everything from the raw events on every call, so a shortcut or off-by-one in the planner shows up
/// as a disagreement.
struct ReferenceModel {
    let calendar: Calendar

    init(firstWeekday: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = firstWeekday
        self.calendar = calendar
    }

    func date(_ day: LocalDay) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
    }

    func localDay(_ date: Date) -> LocalDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    func days(from start: LocalDay, to end: LocalDay) -> Int {
        calendar.dateComponents([.day], from: date(start), to: date(end)).day!
    }

    /// Each day's summed amount for the item, counting each event ID once. Not clamped.
    func sums(for itemID: UUID, in records: [CompletionRecord]) -> [LocalDay: Int] {
        var seen = Set<UUID>()
        var sums: [LocalDay: Int] = [:]
        for record in records where record.itemID == itemID && seen.insert(record.id).inserted {
            sums[record.day, default: 0] += record.amount
        }
        return sums
    }

    func total(for itemID: UUID, on day: LocalDay, in records: [CompletionRecord]) -> Int {
        max(0, sums(for: itemID, in: records)[day] ?? 0)
    }

    /// What the planner should report for this item on this day: `nil` when it isn't listed.
    func expectedEntry(for plan: ItemPlan, on day: LocalDay, records: [CompletionRecord]) -> Expected? {
        guard day >= plan.startDay else { return nil }
        let sums = sums(for: plan.id, in: records)
        let total = max(0, sums[day] ?? 0)
        let doneToday = (plan.kind == .counted ? total : min(total, 1)) >= plan.target

        guard let recurrence = plan.recurrence else {
            return expectedOneOff(plan, on: day, sums: sums, total: total, doneToday: doneToday)
        }
        let completedDays = Set(sums.filter { $0.value >= plan.target }.keys)
        let listed = isDue(recurrence, plan: plan, on: day, completedDays: completedDays, doneToday: doneToday)
        return listed ? Expected(total: total, isCarriedOver: false) : nil
    }

    private func expectedOneOff(
        _ plan: ItemPlan,
        on day: LocalDay,
        sums: [LocalDay: Int],
        total: Int,
        doneToday: Bool
    ) -> Expected? {
        if doneToday {
            return Expected(total: total, isCarriedOver: false)
        }
        if sums.values.contains(where: { $0 > 0 }) {
            return nil
        }
        if let due = plan.dueDay, due > day {
            return nil
        }
        return Expected(total: total, isCarriedOver: plan.dueDay.map { $0 < day } ?? false)
    }

    private func isDue(
        _ recurrence: Recurrence,
        plan: ItemPlan,
        on day: LocalDay,
        completedDays: Set<LocalDay>,
        doneToday: Bool
    ) -> Bool {
        switch recurrence {
        case .daily:
            return true
        case let .everyNDays(interval):
            return days(from: plan.startDay, to: day) % max(1, interval) == 0
        case let .weekly(weekdays):
            return weekdays.contains(calendar.component(.weekday, from: date(day)))
        case let .monthly(rule):
            return monthlyMatches(rule, day: day, start: plan.startDay)
        case let .timesPerWeek(count):
            let weekStart = localDay(calendar.dateInterval(of: .weekOfYear, for: date(day))!.start)
            let doneDays = completedDays.count { $0 >= weekStart && $0 < day }
            return doneToday || doneDays < count
        case let .daysAfterLastDone(interval):
            let lastDone = completedDays.filter { $0 < day }.max()
            let nextDue = lastDone.map {
                localDay(calendar.date(byAdding: .day, value: max(1, interval), to: date($0))!)
            } ?? plan.startDay
            return day >= nextDue
        }
    }

    private func monthlyMatches(_ rule: MonthlyRule, day: LocalDay, start: LocalDay) -> Bool {
        let startMonth = calendar.date(from: DateComponents(year: start.year, month: start.month, day: 1))!
        let thisMonth = calendar.date(from: DateComponents(year: day.year, month: day.month, day: 1))!
        let months = calendar.dateComponents([.month], from: startMonth, to: thisMonth).month!
        guard months >= 0, months % max(1, rule.everyMonths) == 0 else { return false }
        let lastDay = calendar.range(of: .day, in: .month, for: thisMonth)!.count
        switch rule.anchor {
        case let .day(target):
            return day.day == min(max(1, target), lastDay)
        case .lastDay:
            return day.day == lastDay
        }
    }

    struct Expected: Equatable {
        var total: Int
        var isCarriedOver: Bool
    }
}
