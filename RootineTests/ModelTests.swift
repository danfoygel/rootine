import Foundation
import SwiftData
import Testing

@MainActor
struct ModelTests {
    @Test func itemRoundTripsScheduleFieldsThroughStore() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let category = ItemCategory(name: "Health")
        let rule = MonthlyRule(anchor: .lastDay, everyMonths: 3)
        let window = TimeOfDay.window(start: ClockTime(hour: 7), end: ClockTime(hour: 9, minute: 30))
        let item = Item(
            name: "Review",
            kind: .habit,
            recurrence: .monthly(rule),
            timeOfDay: window,
            startDay: LocalDay(year: 2026, month: 1, day: 5),
            category: category
        )
        context.insert(item)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Item>()).first)
        #expect(fetched.plan.recurrence == .monthly(rule))
        #expect(fetched.plan.timeOfDay == window)
        #expect(fetched.plan.startDay == LocalDay(year: 2026, month: 1, day: 5))
        #expect(fetched.category?.name == "Health")
        #expect(category.items?.count == 1)
    }

    @Test func oneOffPlanIgnoresStrayRecurrence() {
        let item = Item(
            name: "Call",
            kind: .oneOff,
            recurrence: .daily,
            dueDay: LocalDay(year: 2026, month: 11, day: 2)
        )
        #expect(item.plan.recurrence == nil)
        #expect(item.plan.dueDay == LocalDay(year: 2026, month: 11, day: 2))
    }

    @Test func eventsFeedTheLedger() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let itemID = UUID()
        let today = LocalDay(year: 2026, month: 10, day: 30)
        context.insert(CompletionEvent(itemID: itemID, day: today, amount: 1))
        context.insert(CompletionEvent(itemID: itemID, day: today, amount: 1))
        try context.save()

        let records = try context.fetch(FetchDescriptor<CompletionEvent>()).compactMap(\.record)
        #expect(CompletionLedger(records).total(for: itemID, on: today) == 2)
    }
}
