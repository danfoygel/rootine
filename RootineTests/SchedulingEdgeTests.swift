import Foundation
import Testing

private let planner = DayPlanner(firstWeekday: 2)

private func entry(
    _ plan: ItemPlan,
    on date: LocalDay = fixedToday,
    _ records: [CompletionRecord] = []
) -> TodayEntry? {
    planner.entry(for: plan, on: date, ledger: CompletionLedger(records))
}

struct StartDayTests {
    static let recurrences: [Recurrence] = [
        .daily, .everyNDays(3), .weekly(Set(1 ... 7)), .monthly(MonthlyRule(anchor: .day(30))),
        .monthly(MonthlyRule(anchor: .lastDay)), .timesPerWeek(2), .daysAfterLastDone(5),
    ]

    @Test(arguments: recurrences)
    func nothingIsListedBeforeTheStartDay(recurrence: Recurrence) {
        let plan = ItemPlan.habit("Future", recurrence, start: fixedToday.adding(days: 1))
        #expect(entry(plan) == nil)
        #expect(entry(.oneOff("Future to-do", start: fixedToday.adding(days: 1))) == nil)
    }

    @Test func itemsCreatedTodayAreListedToday() {
        #expect(entry(.habit("New", .daily, start: fixedToday)) != nil)
        #expect(entry(.habit("New floating", .daysAfterLastDone(7), start: fixedToday)) != nil)
        #expect(entry(.habit("New cadence", .everyNDays(5), start: fixedToday)) != nil)
        #expect(entry(.oneOff("New to-do", start: fixedToday)) != nil)
    }

    @Test func floatingItemWithNoCompletionIsDueFromItsStartDay() {
        let plan = ItemPlan.habit("Plants", .daysAfterLastDone(4), start: fixedToday.adding(days: -10))
        #expect(entry(plan, on: fixedToday.adding(days: -10)) != nil)
        #expect(entry(plan) != nil)
    }
}

struct FirstWeekdayTests {
    private let run = ItemPlan.habit("Run", .timesPerWeek(1), start: day(10, 1))

    @Test func sundayFirstAndMondayFirstWeeksDiffer() {
        // Done on Sunday 2026-11-01: the last day of a Monday-first week, the first of a Sunday-first week.
        let records = done(run, on: day(11, 1))
        let monday = day(11, 2)
        #expect(DayPlanner(firstWeekday: 2).entry(for: run, on: monday, ledger: CompletionLedger(records)) != nil)
        #expect(DayPlanner(firstWeekday: 1).entry(for: run, on: monday, ledger: CompletionLedger(records)) == nil)
    }

    @Test func targetMetOnLastDayOfWeekDoesNotCarryIntoNextWeek() {
        let twice = ItemPlan.habit("Swim", .timesPerWeek(2), start: day(10, 1))
        let records = done(twice, on: day(10, 31), day(11, 1)) // Sat, Sun
        #expect(entry(twice, on: day(11, 2), records) != nil) // new Monday-first week
    }
}

struct TwoDeviceLedgerTests {
    private let stretch = ItemPlan.habit("Stretch")
    private let water = ItemPlan.counted("Water", target: 8)

    @Test func checkedOnBothThenUncheckedOnceIsNotDone() throws {
        var records = done(stretch, on: fixedToday) + done(stretch, on: fixedToday)
        let both = try #require(entry(stretch, records))
        #expect(both.total == 2)
        records += done(stretch, on: fixedToday, amount: both.tapAmount)
        #expect(entry(stretch, records)?.isDone == false)
        #expect(entry(stretch, records)?.total == 0)
    }

    /// Documents a known limit: an un-check made before this device has seen the other device's check-off only
    /// cancels what it saw, so after the merge the item is still done and can be un-checked again.
    @Test func uncheckThatMissedTheOtherDevicesCheckLeavesItDone() throws {
        let phone = done(stretch, on: fixedToday)
        let watch = done(stretch, on: fixedToday)
        let watchUndo = try done(stretch, on: fixedToday, amount: #require(entry(stretch, watch)).tapAmount)
        let merged = phone + watch + watchUndo
        #expect(entry(stretch, merged)?.isDone == true)
    }

    @Test func interleavedCountedTapsFromBothDevicesAddUp() {
        let taps = (0 ..< 5).flatMap { _ in done(water, on: fixedToday) }
        let undo = done(water, on: fixedToday, amount: -1)
        #expect(entry(water, taps + undo)?.total == 4)
        #expect(entry(water, (taps + undo).reversed())?.total == 4)
    }

    @Test func compensatingEventOnADayWithNothingElseClampsToZero() {
        let stray = done(water, on: fixedToday, amount: -3)
        #expect(entry(water, stray)?.total == 0)
        #expect(entry(water, stray)?.undoStepAmount == nil)
    }
}

struct OverdueBoundaryTests {
    private func isOverdue(_ timeOfDay: TimeOfDay, at hour: Int, _ minute: Int, total: Int = 0) -> Bool {
        TodayEntry(plan: .habit("Item", .daily, timeOfDay), total: total)
            .isOverdue(at: ClockTime(hour: hour, minute: minute))
    }

    @Test func exactTimeIsOverdueOnlyAfterItsMinute() {
        #expect(!isOverdue(.at(8), at: 7, 59))
        #expect(!isOverdue(.at(8), at: 8, 0))
        #expect(isOverdue(.at(8), at: 8, 1))
    }

    @Test func windowIsOverdueOnlyAfterItEnds() {
        #expect(!isOverdue(.window(7, 9), at: 8, 59))
        #expect(!isOverdue(.window(7, 9), at: 9, 0))
        #expect(isOverdue(.window(7, 9), at: 9, 1))
    }

    @Test func anytimeAndDoneItemsAreNeverOverdue() {
        #expect(!isOverdue(.anytime, at: 23, 59))
        #expect(!isOverdue(.at(8), at: 23, 59, total: 1))
    }
}
