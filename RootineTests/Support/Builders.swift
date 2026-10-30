import Foundation

// Shared helpers for writing test data tersely (TESTING.md §6.2). Tests still spell out the data they use.

/// The suites' fixed "today": Friday 2026-10-30, in the week of Mon 2026-10-26 … Sun 2026-11-01.
let fixedToday = LocalDay(year: 2026, month: 10, day: 30)

/// A Gregorian calendar in a fixed zone with Monday as the first weekday, matching the fixed week.
let mondayFirstCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

func day(_ month: Int, _ dayOfMonth: Int, year: Int = 2026) -> LocalDay {
    LocalDay(year: year, month: month, day: dayOfMonth)
}

extension ItemPlan {
    static func habit(
        _ name: String,
        _ recurrence: Recurrence = .daily,
        _ timeOfDay: TimeOfDay = .anytime,
        start: LocalDay = day(10, 1),
        category: CategoryRef? = nil
    ) -> ItemPlan {
        ItemPlan(name: name, kind: .habit, recurrence: recurrence, timeOfDay: timeOfDay, startDay: start,
                 category: category)
    }

    static func counted(
        _ name: String,
        target: Int,
        step: Int = 1,
        _ recurrence: Recurrence = .daily,
        start: LocalDay = day(10, 1)
    ) -> ItemPlan {
        ItemPlan(name: name, kind: .counted, recurrence: recurrence, startDay: start, dailyTarget: target,
                 stepSize: step)
    }

    static func oneOff(_ name: String, due: LocalDay? = nil, start: LocalDay = day(10, 1)) -> ItemPlan {
        ItemPlan(name: name, kind: .oneOff, startDay: start, dueDay: due)
    }
}

/// One event of `amount` per day listed.
func done(_ plan: ItemPlan, on days: LocalDay..., amount: Int = 1) -> [CompletionRecord] {
    days.map { CompletionRecord(id: UUID(), itemID: plan.id, day: $0, amount: amount) }
}

/// Activity in `ActivityStrip` notation starting on `start`: `log(plan, from: day(10, 1), "XX.X..X")`.
func log(_ plan: ItemPlan, from start: LocalDay, _ strip: String) -> [CompletionRecord] {
    ActivityStrip.events(strip, from: start, step: plan.stepSize).map {
        CompletionRecord(id: UUID(), itemID: plan.id, day: $0.day, amount: $0.amount)
    }
}

/// Activity in `ActivityStrip` notation whose last character is `last`.
func log(_ plan: ItemPlan, endingOn last: LocalDay, _ strip: String) -> [CompletionRecord] {
    log(plan, from: ActivityStrip.start(of: strip, endingOn: last), strip)
}
