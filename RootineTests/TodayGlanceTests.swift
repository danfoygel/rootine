import Foundation
import Testing

private let today = LocalDay(year: 2026, month: 10, day: 30)
private let start = LocalDay(year: 2026, month: 10, day: 1)

private func habit(_ name: String, _ timeOfDay: TimeOfDay = .anytime) -> ItemPlan {
    ItemPlan(name: name, kind: .habit, recurrence: .daily, timeOfDay: timeOfDay, startDay: start)
}

private func glance(_ entries: [TodayEntry], at now: ClockTime) -> TodayGlance {
    TodayGlance(entries: entries, itemsByID: [:], on: today, at: now)
}

private func date(_ hour: Int, _ minute: Int = 0) -> Date {
    ClockTime(hour: hour, minute: minute).date(on: today)
}

struct TodayGlanceTests {
    @Test func entriesFollowUrgencyOrderWithDoneLast() {
        let built = glance([
            TodayEntry(plan: habit("Read"), total: 0),
            TodayEntry(plan: habit("Walk", .exact(ClockTime(hour: 18))), total: 0),
            TodayEntry(plan: habit("Water"), total: 1),
            TodayEntry(plan: habit("Vitamins", .exact(ClockTime(hour: 8))), total: 0),
        ], at: ClockTime(hour: 10))
        #expect(built.entries.map(\.name) == ["Vitamins", "Walk", "Read", "Water"])
        #expect(built.remaining.count == 3)
        #expect(built.doneCount == 1)
    }

    @Test func overdueMatchesTheListAMinuteAfterDue() {
        let entry = TodayEntry(plan: habit("Walk", .exact(ClockTime(hour: 18))), total: 0)
        let walk = glance([entry], at: ClockTime(hour: 9)).entries[0]
        for (hour, minute) in [(17, 59), (18, 0), (18, 1), (19, 0)] {
            let listSays = entry.isOverdue(at: ClockTime(hour: hour, minute: minute))
            #expect(walk.isOverdue(at: date(hour, minute)) == listSays)
        }
        #expect(!walk.isOverdue(at: date(18)))
        #expect(walk.isOverdue(at: date(18, 1)))
    }

    @Test func changeDatesCoverUpcomingOverdueAndMidnight() {
        let built = glance([
            TodayEntry(plan: habit("Vitamins", .exact(ClockTime(hour: 8))), total: 0),
            TodayEntry(plan: habit("Walk", .exact(ClockTime(hour: 18))), total: 0),
            TodayEntry(plan: habit("Stretch", .exact(ClockTime(hour: 20))), total: 1),
        ], at: ClockTime(hour: 10))
        let midnight = LocalDay(year: 2026, month: 10, day: 31).startDate()
        #expect(built.changeDates(after: date(10)) == [date(18, 1), midnight])
    }

    @Test func goesStaleTheNextDay() {
        let built = glance([], at: ClockTime(hour: 10))
        #expect(built.isCurrent(at: date(23, 59)))
        #expect(!built.isCurrent(at: LocalDay(year: 2026, month: 10, day: 31).startDate()))
    }
}
