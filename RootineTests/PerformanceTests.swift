import Foundation
import SwiftData
import Testing

extension Tag {
    /// Timing budgets on the `heavy` scenario; run with `-skip-testing` or a tag filter to leave them out.
    @Tag static var performance: Self
}

/// Median wall-clock time of `body` over `runs` runs.
private func median(runs: Int = 5, _ body: () throws -> Void) rethrows -> Duration {
    let clock = ContinuousClock()
    var times: [Duration] = []
    for _ in 0 ..< runs {
        try times.append(clock.measure(body))
    }
    return times.sorted()[runs / 2]
}

/// Budgets for the work the Today list repeats every minute, on a year of history for 60 items (about 12k events).
/// Measured on the iPhone 17 simulator (M-series Mac, Oct 2026): ledger 5.4 ms, planner 0.15 ms, TodayData from
/// the store 25 ms, relay encoding 0.9 ms. Budgets are about 3–4× those, with a 2 ms floor, so local noise doesn't
/// cause flakes (TESTING.md §6.4). CI skips this suite: its runners are too slow and variable (TESTING.md §11).
@Suite(.tags(.performance))
@MainActor
struct PerformanceTests {
    private let data = Scenario.heavy.data(today: fixedToday, calendar: mondayFirstCalendar)

    @Test func heavyScenarioIsTheSizeItClaims() {
        #expect(data.items.count == 60)
        #expect(data.events.count > 10000)
    }

    @Test func buildingTheLedger() {
        let records = data.records
        let time = median { _ = CompletionLedger(records) }
        #expect(time < .milliseconds(20), "CompletionLedger took \(time)")
    }

    @Test func planningTheDay() {
        let ledger = CompletionLedger(data.records)
        let plans = data.plans
        let time = median { _ = DayPlanner(firstWeekday: 2).entries(on: fixedToday, items: plans, ledger: ledger) }
        #expect(time < .milliseconds(2), "DayPlanner took \(time)")
    }

    /// The whole per-minute recompute from store models, including decoding each item's schedule.
    @Test func buildingTodayDataFromTheStore() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try context.load(data)
        let items = try context.fetch(FetchDescriptor<Item>())
        let events = try context.fetch(FetchDescriptor<CompletionEvent>())
        let time = median { _ = TodayData(on: fixedToday, items: items, events: events, relay: RelayState()) }
        #expect(time < .milliseconds(80), "TodayData took \(time)")
    }

    @Test func encodingTheRelayLibrary() {
        let library = ItemLibrary(items: data.items, deletedIDs: [], sentAt: .now)
        let time = median { _ = RelayPayload.message(library: library) }
        #expect(time < .milliseconds(5), "Encoding the library took \(time)")
    }
}
