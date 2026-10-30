import Foundation
import SwiftData
import Testing

private let start = LocalDay(year: 2026, month: 10, day: 1)
private let today = LocalDay(year: 2026, month: 10, day: 30)

private func habit(
    _ name: String,
    _ timeOfDay: TimeOfDay = .anytime,
    category: CategoryRef? = nil
) -> ItemPlan {
    ItemPlan(name: name, kind: .habit, recurrence: .daily, timeOfDay: timeOfDay, startDay: start, category: category)
}

struct TapAmountTests {
    @Test func habitChecksAndUnchecksWholeTotal() {
        #expect(TodayEntry(plan: habit("Stretch"), total: 0).tapAmount == 1)
        #expect(TodayEntry(plan: habit("Stretch"), total: 1).tapAmount == -1)
        // Checked off on both devices: un-checking must cancel both.
        #expect(TodayEntry(plan: habit("Stretch"), total: 2).tapAmount == -2)
        #expect(TodayEntry(plan: habit("Stretch"), total: 2).undoStepAmount == nil)
    }

    @Test func countedStepsAndUndo() {
        let water = ItemPlan(
            name: "Water", kind: .counted, recurrence: .daily, startDay: start, dailyTarget: 2000, stepSize: 250
        )
        #expect(TodayEntry(plan: water, total: 0).tapAmount == 250)
        #expect(TodayEntry(plan: water, total: 2000).tapAmount == 250) // can go past the target
        #expect(TodayEntry(plan: water, total: 0).undoStepAmount == nil)
        #expect(TodayEntry(plan: water, total: 100).undoStepAmount == -100)
        #expect(TodayEntry(plan: water, total: 750).undoStepAmount == -250)
        #expect(TodayEntry(plan: water, total: 750).resetAmount == -750)
    }
}

struct TodayLayoutTests {
    private let health = CategoryRef(id: UUID(), name: "Health", sortOrder: 0)
    private let home = CategoryRef(id: UUID(), name: "Home", sortOrder: 1)

    private var entries: [TodayEntry] {
        [
            TodayEntry(plan: habit("Read", .at(21), category: home), total: 0),
            TodayEntry(plan: habit("Vitamins", .at(8), category: health), total: 0),
            TodayEntry(plan: habit("Walk", .window(start: ClockTime(hour: 12), end: ClockTime(hour: 14))), total: 1),
            TodayEntry(plan: habit("Floss", category: health), total: 0),
            TodayEntry(plan: habit("Coffee", .at(7), category: home), total: 1),
        ]
    }

    private func shape(_ sections: [TodaySection]) -> [String] {
        sections.map { "\($0.title ?? "-"): " + $0.entries.map(\.plan.name).joined(separator: ",") }
    }

    @Test func byTimeBucketsByReminderTime() {
        #expect(shape(TodayLayout.byTime.sections(for: entries, at: ClockTime(hour: 10))) == [
            "Morning: Coffee,Vitamins",
            "Afternoon: Walk",
            "Evening: Read",
            "Anytime: Floss",
        ])
    }

    @Test func byCategoryOrdersCategoriesThenOther() {
        // Within a category, urgency order: Vitamins (8am) is overdue at 10am; done items sink.
        #expect(shape(TodayLayout.byCategory.sections(for: entries, at: ClockTime(hour: 10))) == [
            "Health: Vitamins,Floss",
            "Home: Read,Coffee",
            "Other: Walk",
        ])
    }

    @Test func byUrgencyIsOneUntitledSection() {
        #expect(shape(TodayLayout.byUrgency.sections(for: entries, at: ClockTime(hour: 10))) == [
            "-: Vitamins,Read,Floss,Coffee,Walk"
        ])
        #expect(TodayLayout.byUrgency.sections(for: [], at: ClockTime(hour: 10)).isEmpty)
    }
}

@MainActor
struct ItemDraftTests {
    private func roundTrip(_ configure: (inout ItemDraft) -> Void) -> ItemDraft {
        var draft = ItemDraft(today: today)
        draft.name = "  Thing  "
        configure(&draft)
        let item = Item(name: "", kind: .habit)
        draft.apply(to: item, category: nil)
        return ItemDraft(item: item, today: today)
    }

    @Test(arguments: [
        Recurrence.daily,
        .everyNDays(3),
        .weekly([1, 7]),
        .monthly(MonthlyRule(anchor: .day(31), everyMonths: 3)),
        .monthly(MonthlyRule(anchor: .lastDay)),
        .timesPerWeek(4),
        .daysAfterLastDone(10),
    ])
    func recurrenceSurvivesRoundTrip(recurrence: Recurrence) {
        let item = Item(name: "Thing", kind: .habit, recurrence: recurrence)
        #expect(ItemDraft(item: item, today: today).recurrence == recurrence)
    }

    @Test func trimsNameAndKeepsTimeWindow() {
        let window = TimeOfDay.window(start: ClockTime(hour: 6, minute: 30), end: ClockTime(hour: 8))
        let loaded = roundTrip { draft in
            draft.timeMode = .window
            draft.windowStart = ClockTime(hour: 6, minute: 30)
            draft.windowEnd = ClockTime(hour: 8)
        }
        #expect(loaded.name == "Thing")
        #expect(loaded.timeOfDay == window)
    }

    @Test func oneOffDropsRecurrenceAndKeepsDueDay() {
        let due = LocalDay(year: 2026, month: 11, day: 4)
        let loaded = roundTrip { draft in
            draft.kind = .oneOff
            draft.pattern = .weekly
            draft.hasDueDay = true
            draft.dueDay = due
        }
        #expect(loaded.recurrence == nil)
        #expect(loaded.hasDueDay)
        #expect(loaded.dueDay == due)
    }

    @Test func countedFieldsOnlyKeptForCountedItems() {
        let habitDraft = roundTrip { draft in
            draft.unit = "ml"
            draft.dailyTarget = 2000
        }
        #expect(habitDraft.unit.isEmpty)
        #expect(habitDraft.dailyTarget == 1)

        let counted = roundTrip { draft in
            draft.kind = .counted
            draft.unit = " ml "
            draft.dailyTarget = 2000
            draft.stepSize = 250
        }
        #expect(counted.unit == "ml")
        #expect(counted.dailyTarget == 2000)
        #expect(counted.stepSize == 250)
    }

    @Test func problemsBlockSaving() {
        var draft = ItemDraft(today: today)
        #expect(draft.problem != nil)
        draft.name = "Gym"
        #expect(draft.problem == nil)
        draft.pattern = .weekly
        draft.weekdays = []
        #expect(draft.problem != nil)
        draft.kind = .oneOff
        #expect(draft.problem == nil) // one-offs ignore the pattern
        draft.timeMode = .window
        draft.windowEnd = draft.windowStart
        #expect(draft.problem != nil)
    }
}

struct RowDetailTests {
    @Test func countedShowsProgressAndUnit() {
        let water = ItemPlan(name: "Water", kind: .counted, recurrence: .daily, startDay: start, dailyTarget: 8)
        #expect(TodayEntry(plan: water, total: 3).detail(unit: "glasses", isOverdue: false) == "3 / 8 glasses")
        #expect(TodayEntry(plan: water, total: 3).detail(unit: "", isOverdue: false) == "3 / 8")
    }

    @Test func overdueComesFirstAndAnytimeHabitHasNoDetail() throws {
        let timed = TodayEntry(plan: habit("Vitamins", .at(8)), total: 0)
        let detail = try #require(timed.detail(unit: "", isOverdue: true))
        #expect(detail.hasPrefix("Overdue · "))
        #expect(TodayEntry(plan: habit("Floss"), total: 0).detail(unit: "", isOverdue: false) == nil)
    }

    @Test func carriedOverShowsDueDate() throws {
        let plan = ItemPlan(
            name: "Call",
            kind: .oneOff,
            startDay: start,
            dueDay: LocalDay(year: 2026, month: 10, day: 28)
        )
        let entry = TodayEntry(plan: plan, total: 0, isCarriedOver: true)
        let detail = try #require(entry.detail(unit: "", isOverdue: true))
        #expect(detail.hasPrefix("Due "))
        #expect(!detail.contains("Overdue"))
    }
}
