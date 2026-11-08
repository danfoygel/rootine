import Foundation
import SwiftData
import Testing

/// Screen Time logged through the day (hourly automations): limits wait for the day to end, and re-runs update
/// readings in place.
@MainActor
struct SameDayReadingTests {
    private let limit = ItemLink(metric: .screenTime, subject: "Instagram", rule: .atMost(3600), unit: .seconds,
                                 accumulates: true)
    private let goal = ItemLink(metric: .screenTime, subject: "Kindle", rule: .atLeast(1800), unit: .seconds,
                                accumulates: true)

    private func reading(_ subject: String, _ seconds: Double, on day: LocalDay = fixedToday) -> ReadingValue {
        ReadingValue(source: .screenTime, metric: .screenTime, subject: subject, day: day, start: day.startDate(),
                     end: day.adding(days: 1).startDate(), value: seconds)
    }

    private func linked(_ name: String, _ link: ItemLink) -> ItemPlan {
        var plan = ItemPlan.habit(name)
        plan.link = link
        return plan
    }

    @Test func anAccumulatingLimitIsOnlyMetOnceTheDayIsOver() {
        #expect(limit.progress(for: 600, target: 1, dayIsOver: false) == 0)
        #expect(limit.progress(for: 600, target: 1, dayIsOver: true) == 1)
        // Goals complete as soon as they're reached.
        #expect(goal.progress(for: 1800, target: 1, dayIsOver: false) == 1)
        // A limit on a final value (a wake-up time) doesn't wait.
        var wake = limit
        wake.accumulates = nil
        #expect(wake.progress(for: 600, target: 1, dayIsOver: false) == 1)
    }

    @Test func theEvaluatorWaitsForTodayButNotForEarlierDays() {
        let item = linked("Under 1h Instagram", limit)
        let today = ReadingEvaluator.changes(items: [item], readings: [reading("Instagram", 600)], autoTotals: [:],
                                             on: fixedToday, today: fixedToday)
        #expect(today.isEmpty)
        let yesterday = fixedToday.adding(days: -1)
        let settled = ReadingEvaluator.changes(
            items: [item], readings: [reading("Instagram", 600, on: yesterday)], autoTotals: [:], on: yesterday,
            today: fixedToday
        )
        #expect(settled == [item.id: 1])
    }

    @Test func linksSavedBeforeAccumulatesStillDecode() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(limit)) as? [String: Any])
        json["accumulates"] = nil
        let link = try JSONDecoder().decode(ItemLink.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(link.accumulates == nil)
        #expect(link.subject == "Instagram")
    }

    @Test func replacingUpdatesReadingsInPlace() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let first = Date(timeIntervalSinceReferenceDate: 0)
        try context.replaceReadings([reading("Instagram", 600), reading("Safari", 60)], from: .screenTime,
                                    on: fixedToday, now: first)
        func stored() throws -> [String: Reading] {
            try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<Reading>()).map { ($0.subject, $0) })
        }
        let before = try stored()

        // An hour later: Instagram grew, Safari is unchanged, Notes is new.
        let later = first.addingTimeInterval(3600)
        try context.replaceReadings([reading("Instagram", 900), reading("Safari", 60), reading("Notes", 30)],
                                    from: .screenTime, on: fixedToday, now: later)
        let after = try stored()
        #expect(after["Instagram"]?.id == before["Instagram"]?.id)
        #expect(after["Instagram"]?.value == 900)
        #expect(after["Instagram"]?.recordedAt == later)
        #expect(after["Safari"]?.id == before["Safari"]?.id)
        #expect(after["Safari"]?.recordedAt == first)
        #expect(after["Notes"]?.value == 30)

        // A run without Safari removes it.
        try context.replaceReadings([reading("Instagram", 900)], from: .screenTime, on: fixedToday, now: later)
        #expect(try stored().keys.sorted() == ["Instagram"])
    }

    @Test func aLimitLoggedDuringTheDaySettlesWithTheNextMorningsRun() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let item = Item(name: "Under 1h Instagram", kind: .habit, startDay: day(10, 1))
        item.link = limit
        context.insert(item)
        func isDone() throws -> Bool {
            let events = try context.fetch(FetchDescriptor<CompletionEvent>()).compactMap(\.record)
            return DayPlanner().entry(for: item.plan, on: fixedToday, ledger: CompletionLedger(events))?.isDone == true
        }
        let noon = fixedToday.startDate().addingTimeInterval(12 * 3600)
        try context.replaceReadings([reading("Instagram", 600)], from: .screenTime, on: fixedToday, now: noon)
        #expect(try !isDone())
        let nextMorning = fixedToday.adding(days: 1).startDate().addingTimeInterval(6 * 3600)
        try context.replaceReadings([reading("Instagram", 2400)], from: .screenTime, on: fixedToday, now: nextMorning)
        #expect(try isDone())
    }
}

/// The Settings view's day summary, for comparing with Settings → Screen Time.
struct ScreenTimeDayTests {
    @Test(arguments: [
        (0.0, "0s"), (59.9, "59s"), (60, "1m"), (719, "11m 59s"), (3600, "1h"), (4000, "1h 6m 40s"),
        (3605, "1h 5s"), (-5, "0s"),
    ])
    func formatLikeScreenTime(_ seconds: Double, _ text: String) {
        #expect(ScreenTimeDay.format(seconds) == text)
    }

    @Test func oneDaysAppsAndWebsitesMostUsedFirst() {
        let yesterday = fixedToday.adding(days: -1)
        let report = ScreenTimeReport(apps: "Safari (1h 35m)\nNotes (5m)\nMaps (5m)", websites: "apple.com (20m)")
        let other = ReadingValue(source: ReadingSource(rawValue: "health"), metric: .screenTime, subject: "Notes",
                                 day: fixedToday, start: fixedToday.startDate(), value: 999)
        let readings = report.readings(on: fixedToday) + report.readings(on: yesterday) + [other]
        let day = ScreenTimeDay(readings: readings, on: fixedToday)
        #expect(day.apps.map(\.name) == ["Safari", "Maps", "Notes"])
        #expect(day.websites.map(\.seconds) == [1200])
        #expect(day.total == 5700 + 600)
        #expect(ScreenTimeDay(readings: readings, on: fixedToday.adding(days: -2)).isEmpty)
    }
}
