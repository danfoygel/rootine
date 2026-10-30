import Foundation
import Testing

/// Week of Mon 2026-10-26 … Sun 2026-11-01, with Monday as the first weekday.
private func day(_ month: Int, _ dayOfMonth: Int, year: Int = 2026) -> LocalDay {
    LocalDay(year: year, month: month, day: dayOfMonth)
}

private let planner = DayPlanner(firstWeekday: 2)

private func done(_ plan: ItemPlan, on days: LocalDay..., amount: Int = 1) -> [CompletionRecord] {
    days.map { CompletionRecord(id: UUID(), itemID: plan.id, day: $0, amount: amount) }
}

private func isListed(_ plan: ItemPlan, on listDay: LocalDay, _ records: [CompletionRecord] = []) -> Bool {
    planner.entry(for: plan, on: listDay, ledger: CompletionLedger(records)) != nil
}

struct FixedRecurrenceTests {
    @Test func dailyStartsOnStartDay() {
        let plan = ItemPlan(name: "Vitamins", kind: .habit, recurrence: .daily, startDay: day(10, 28))
        #expect(!isListed(plan, on: day(10, 27)))
        #expect(isListed(plan, on: day(10, 28)))
        #expect(isListed(plan, on: day(11, 15)))
    }

    @Test func everyNDaysCountsFromStart() {
        let plan = ItemPlan(name: "Floss", kind: .habit, recurrence: .everyNDays(3), startDay: day(10, 26))
        let listed = (0 ..< 9).map { isListed(plan, on: day(10, 26).adding(days: $0)) }
        #expect(listed == [true, false, false, true, false, false, true, false, false])
    }

    @Test func weeklyOnChosenWeekdays() {
        let plan = ItemPlan(name: "Gym", kind: .habit, recurrence: .weekly([2, 4, 6]), startDay: day(10, 1))
        #expect(isListed(plan, on: day(10, 26))) // Mon
        #expect(!isListed(plan, on: day(10, 27))) // Tue
        #expect(isListed(plan, on: day(10, 30))) // Fri
        #expect(!isListed(plan, on: day(11, 1))) // Sun
    }

    @Test func monthlyFixedDayClampsInShortMonths() {
        let rule = MonthlyRule(anchor: .day(31))
        let plan = ItemPlan(name: "Bills", kind: .habit, recurrence: .monthly(rule), startDay: day(1, 1))
        #expect(isListed(plan, on: day(1, 31)))
        #expect(isListed(plan, on: day(2, 28)))
        #expect(!isListed(plan, on: day(2, 27)))
        #expect(isListed(plan, on: day(4, 30)))
        #expect(isListed(plan, on: day(2, 29, year: 2028)))
        #expect(!isListed(plan, on: day(2, 28, year: 2028)))
    }

    @Test func monthlyLastDay() {
        let plan = ItemPlan(
            name: "Review",
            kind: .habit,
            recurrence: .monthly(MonthlyRule(anchor: .lastDay)),
            startDay: day(1, 1)
        )
        #expect(isListed(plan, on: day(10, 31)))
        #expect(!isListed(plan, on: day(10, 30)))
        #expect(isListed(plan, on: day(11, 30)))
    }

    @Test func everyNMonthsAnchorsOnStartMonth() {
        let rule = MonthlyRule(anchor: .day(15), everyMonths: 3)
        let plan = ItemPlan(name: "Filter", kind: .habit, recurrence: .monthly(rule), startDay: day(2, 10))
        #expect(isListed(plan, on: day(2, 15)))
        #expect(!isListed(plan, on: day(3, 15)))
        #expect(isListed(plan, on: day(5, 15)))
        #expect(isListed(plan, on: day(2, 15, year: 2027)))
        #expect(!isListed(plan, on: day(1, 15))) // before start
    }
}

struct FlexibleRecurrenceTests {
    private let plan = ItemPlan(name: "Run", kind: .habit, recurrence: .timesPerWeek(2), startDay: day(10, 1))

    @Test func timesPerWeekHidesOnceTargetMet() {
        let records = done(plan, on: day(10, 26), day(10, 27))
        #expect(isListed(plan, on: day(10, 27), records)) // done today: stays visible
        #expect(!isListed(plan, on: day(10, 28), records))
        #expect(!isListed(plan, on: day(11, 1), records))
        #expect(isListed(plan, on: day(11, 2), records)) // new week
    }

    @Test func timesPerWeekStaysListedUntilMet() {
        let records = done(plan, on: day(10, 26))
        #expect(isListed(plan, on: day(10, 30), records))
    }

    @Test func timesPerWeekCountsDaysNotTaps() {
        let records = done(plan, on: day(10, 26), day(10, 26))
        #expect(isListed(plan, on: day(10, 27), records))
    }

    @Test func daysAfterLastDoneFloats() {
        let plan = ItemPlan(name: "Plants", kind: .habit, recurrence: .daysAfterLastDone(4), startDay: day(10, 20))
        #expect(isListed(plan, on: day(10, 20)))
        #expect(isListed(plan, on: day(10, 22))) // never done, so stays due

        let records = done(plan, on: day(10, 22))
        #expect(isListed(plan, on: day(10, 22), records))
        #expect(!isListed(plan, on: day(10, 23), records))
        #expect(!isListed(plan, on: day(10, 25), records))
        #expect(isListed(plan, on: day(10, 26), records))
        #expect(isListed(plan, on: day(10, 28), records)) // missed, still due
    }
}

struct OneOffTests {
    @Test func undatedRollsForwardUntilDone() {
        let plan = ItemPlan(name: "Call bank", kind: .oneOff, startDay: day(10, 20))
        let entry = planner.entry(for: plan, on: day(10, 30), ledger: CompletionLedger([]))
        #expect(entry?.isCarriedOver == false)

        let records = done(plan, on: day(10, 29))
        #expect(isListed(plan, on: day(10, 29), records))
        #expect(!isListed(plan, on: day(10, 30), records))
    }

    @Test func datedHiddenBeforeDueAndCarriedOverAfter() {
        let plan = ItemPlan(name: "Renew", kind: .oneOff, startDay: day(10, 1), dueDay: day(10, 28))
        #expect(!isListed(plan, on: day(10, 27)))
        #expect(planner.entry(for: plan, on: day(10, 28), ledger: CompletionLedger([]))?.isCarriedOver == false)
        #expect(planner.entry(for: plan, on: day(10, 30), ledger: CompletionLedger([]))?.isCarriedOver == true)
    }

    @Test func undoReopensIt() {
        let plan = ItemPlan(name: "Call bank", kind: .oneOff, startDay: day(10, 20))
        let records = done(plan, on: day(10, 29)) + done(plan, on: day(10, 29), amount: -1)
        let entry = planner.entry(for: plan, on: day(10, 30), ledger: CompletionLedger(records))
        #expect(entry?.isDone == false)
    }
}

struct CountedAndLedgerTests {
    private let water = ItemPlan(
        name: "Water",
        kind: .counted,
        recurrence: .daily,
        startDay: day(10, 1),
        dailyTarget: 8
    )

    private func entry(_ records: [CompletionRecord]) -> TodayEntry? {
        planner.entry(for: water, on: day(10, 30), ledger: CompletionLedger(records))
    }

    @Test func countedProgressAndCompletion() {
        let taps = Array(repeating: day(10, 30), count: 5)
        #expect(entry(taps.flatMap { done(water, on: $0) })?.progress == 5)
        #expect(entry(taps.flatMap { done(water, on: $0) })?.isDone == false)
        #expect(entry(done(water, on: day(10, 30), amount: 8))?.isDone == true)
    }

    @Test func duplicateEventIDsCountOnce() {
        let record = CompletionRecord(id: UUID(), itemID: water.id, day: day(10, 30), amount: 1)
        #expect(entry([record, record])?.progress == 1)
    }

    @Test func undoNeverGoesNegative() {
        #expect(entry(done(water, on: day(10, 30), amount: -1))?.progress == 0)
    }
}

struct UrgencyOrderingTests {
    @Test func overdueThenTimedThenUntimedThenDone() {
        let start = day(10, 1)
        let today = day(10, 30)
        let carried = ItemPlan(name: "Carried", kind: .oneOff, startDay: start, dueDay: day(10, 29))
        let late = ItemPlan(name: "Late", kind: .habit, recurrence: .daily, timeOfDay: .exact(.init(hour: 8)),
                            startDay: start)
        let window = ItemPlan(name: "Window", kind: .habit, recurrence: .daily,
                              timeOfDay: .window(start: .init(hour: 9), end: .init(hour: 11)), startDay: start)
        let evening = ItemPlan(name: "Evening", kind: .habit, recurrence: .daily, timeOfDay: .exact(.init(hour: 20)),
                               startDay: start)
        let anytime = ItemPlan(name: "Anytime", kind: .habit, recurrence: .daily, startDay: start)
        let finished = ItemPlan(name: "Finished", kind: .habit, recurrence: .daily, timeOfDay: .exact(.init(hour: 7)),
                                startDay: start)

        let plans = [anytime, finished, evening, window, late, carried]
        let entries = planner.entries(on: today, items: plans, ledger: CompletionLedger(done(finished, on: today)))
        let names = entries.sortedByUrgency(at: ClockTime(hour: 10)).map(\.plan.name)
        #expect(names == ["Carried", "Late", "Window", "Evening", "Anytime", "Finished"])
    }
}
