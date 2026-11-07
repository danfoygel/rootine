import Foundation
import SwiftData
import Testing

// Fixtures in the shapes the shortcut can hand `LogScreenTimeIntent` (DATA.md §1): the action's list passed
// straight to a text parameter (one `Name (1h 35m)` per line), or rows built with a Dictionary per item.

/// Get App & Website Activity, Type = Apps, as text.
private let appsText = """
Safari (1h 35m)
Instagram (52m 10s)
com.nytimes.NYTimes (12m)
Calendar (59s)
"""

/// Get App & Website Activity, Type = Websites, as text.
private let websitesText = """
youtube.com (40m)
en.wikipedia.org (5m 3s)
"""

/// Dictionary rows: duration as seconds, as text, missing (falling back to the description), in any key case,
/// and a few rows that can't be read.
private let rowsJSON = """
[
  {"app": "Kindle", "website": "", "duration": 1830},
  {"App": "Instagram", "Duration": "1h 2m 3s"},
  {"app": "Messages", "description": "Messages (4m)"},
  {"website": "github.com", "duration": "25 min"},
  {"description": "Maps (1 hr, 5 min)"},
  {"app": "Kindle", "duration": 30},
  {"app": "", "duration": 60},
  {"app": "Clock", "duration": "a while"},
  {"app": "Wallet", "duration": true},
  {"app": "Photos", "duration": -5},
  42
]
"""

struct ScreenTimeParsingTests {
    @Test(arguments: [
        ("95", 95.0), ("0", 0), ("12.5", 12.5), ("1h 2m 3s", 3723), ("1h 35m", 5700), ("59s", 59),
        ("1 hr, 35 min", 5700), ("2 hours 5 minutes", 7500), ("3 secs", 3), ("1:02:03", 3723), ("4:05", 245),
    ])
    func durationText(_ text: String, _ seconds: Double) {
        #expect(ScreenTimeReport.seconds(from: text) == seconds)
    }

    @Test(arguments: ["", " ", "about an hour", "5 apples", "1h banana", "h", "-5", "nan", "inf", "1::2",
                      "1:2:3:4", "1:x"])
    func unreadableDurationText(_ text: String) {
        #expect(ScreenTimeReport.seconds(from: text) == nil)
    }

    @Test func descriptionForm() throws {
        let safari = try #require(ScreenTimeReport.described("Safari (1h 35m)"))
        #expect(safari.name == "Safari" && safari.seconds == 5700)
        // Only the last parentheses are the time.
        let beta = try #require(ScreenTimeReport.described(" TestFlight (Beta) (2m) "))
        #expect(beta.name == "TestFlight (Beta)" && beta.seconds == 120)
        for text in ["Safari", "(5m)", "Safari (soon)", "Safari (5m) extra"] {
            #expect(ScreenTimeReport.described(text) == nil)
        }
    }

    @Test func actionTextGivesOneRowPerLine() {
        let report = ScreenTimeReport(apps: appsText, websites: websitesText)
        #expect(report.apps == ["Safari": 5700, "Instagram": 3130, "com.nytimes.NYTimes": 720, "Calendar": 59])
        #expect(report.websites == ["youtube.com": 2400, "en.wikipedia.org": 303])
        #expect(report.skipped == 0)
    }

    @Test func jsonRowsWithSecondsTextAndDescriptions() {
        let report = ScreenTimeReport(apps: rowsJSON)
        // Kindle is listed twice and added up; the website row goes to websites although it came in as apps.
        #expect(report.apps == ["Kindle": 1860, "Instagram": 3723, "Messages": 240, "Maps": 3900])
        #expect(report.websites == ["github.com": 1500])
        // No name, unreadable text, a boolean, a negative number, and a bare number.
        #expect(report.skipped == 5)
    }

    @Test func oneObjectPerLineAndSingleObjects() {
        let lines = """
        {"app":"Instagram","duration":600}

        {"website":"youtube.com","duration":"10m"}
        not a row
        """
        let report = ScreenTimeReport(apps: lines)
        #expect(report.apps == ["Instagram": 600])
        #expect(report.websites == ["youtube.com": 600])
        #expect(report.skipped == 1)

        #expect(ScreenTimeReport(websites: #"{"website":"x.com","duration":5}"#).websites == ["x.com": 5])
    }

    @Test func emptyInputIsAnEmptyReport() {
        for report in [ScreenTimeReport(), ScreenTimeReport(apps: "", websites: " \n "), ScreenTimeReport(apps: "[]")] {
            #expect(report.isEmpty)
            #expect(report.skipped == 0)
            #expect(report.readings(on: fixedToday).isEmpty)
        }
    }

    @Test func oneReadingPerAppAndWebsiteForTheDay() {
        let calendar = mondayFirstCalendar
        let report = ScreenTimeReport(apps: "Safari (1h)\nSafari (30m)\nNotes (1m)", websites: "apple.com (20m)")
        let readings = report.readings(on: fixedToday, calendar: calendar)
        #expect(readings.map(\.subject) == ["Notes", "Safari", "apple.com"])
        #expect(readings.map(\.metric) == [.screenTime, .screenTime, .websiteTime])
        #expect(readings.map(\.value) == [60, 5400, 1200])
        for reading in readings {
            #expect(reading.source == .screenTime)
            #expect(reading.day == fixedToday)
            #expect(reading.start == fixedToday.startDate(calendar: calendar))
            #expect(reading.end == fixedToday.adding(days: 1).startDate(calendar: calendar))
        }
    }

    @Test func linkedAppsMissingFromARunReadZero() {
        let links = [
            ItemLink(metric: .screenTime, subject: "TikTok", rule: .atMost(600), unit: .seconds),
            ItemLink(metric: .screenTime, subject: "Notes", rule: .atLeast(60), unit: .seconds),
            ItemLink(metric: .screenTime, rule: .atMost(7200), unit: .seconds),
            ItemLink(metric: .websiteTime, subject: "youtube.com", rule: .atMost(600), unit: .seconds),
        ]
        let readings = ScreenTimeReport(apps: "Notes (1m)").readings(on: fixedToday, linkedTo: links)
        // TikTok wasn't used: zero. The websites run returned nothing, so youtube.com stays unknown.
        #expect(readings.map(\.subject) == ["Notes", "TikTok"])
        #expect(readings.map(\.value) == [60, 0])
    }
}

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

#if os(iOS)
    /// `LogScreenTimeIntent` end to end against an in-memory store.
    @MainActor
    struct LogScreenTimeIntentTests {
        private let yesterday = fixedToday.adding(days: -1)

        private func makeStore() throws -> DataStore {
            let noon = fixedToday.startDate().addingTimeInterval(12 * 3600)
            return try DataStore(ephemeral: nil, relay: .inert, clock: AppClock(fixedNow: noon))
        }

        private func insertLinked(_ name: String, _ link: ItemLink, into store: DataStore) -> Item {
            let item = Item(name: name, kind: .habit, startDay: day(10, 1))
            item.link = link
            store.container.mainContext.insert(item)
            return item
        }

        private func isDone(_ item: Item, on day: LocalDay, in store: DataStore) throws -> Bool {
            let events = try store.container.mainContext.fetch(FetchDescriptor<CompletionEvent>()).compactMap(\.record)
            return DayPlanner().entry(for: item.plan, on: day, ledger: CompletionLedger(events))?.isDone == true
        }

        private func readings(in store: DataStore) throws -> [ReadingValue] {
            try store.container.mainContext.fetch(FetchDescriptor<Reading>()).compactMap(\.snapshot)
                .sorted { ($0.metric.rawValue, $0.subject) < ($1.metric.rawValue, $1.subject) }
        }

        @Test func logsYesterdayAndCompletesLinkedItems() async throws {
            let store = try makeStore()
            let instagram = insertLinked(
                "Under 1h Instagram",
                ItemLink(metric: .screenTime, subject: "Instagram", rule: .atMost(3600), unit: .seconds),
                into: store
            )
            let tiktok = insertLinked(
                "No TikTok",
                ItemLink(metric: .screenTime, subject: "TikTok", rule: .atMost(0), unit: .seconds),
                into: store
            )
            let youtube = insertLinked(
                "Under 30m YouTube",
                ItemLink(metric: .websiteTime, subject: "youtube.com", rule: .atMost(1800), unit: .seconds),
                into: store
            )

            let intent = LogScreenTimeIntent()
            intent.store = store
            intent.apps = appsText
            intent.websites = websitesText
            _ = try await intent.perform()

            let logged = try readings(in: store)
            #expect(logged.count == 7)
            #expect(logged.allSatisfy { $0.source == .screenTime && $0.day == yesterday })
            #expect(logged.first { $0.subject == "TikTok" }?.value == 0)
            #expect(try isDone(instagram, on: yesterday, in: store))
            #expect(try isDone(tiktok, on: yesterday, in: store))
            #expect(try !isDone(youtube, on: yesterday, in: store))
            #expect(try !isDone(instagram, on: fixedToday, in: store))

            // The automation running again changes nothing.
            _ = try await intent.perform()
            #expect(try readings(in: store).map(\.value) == logged.map(\.value))
            let events = try store.container.mainContext.fetch(FetchDescriptor<CompletionEvent>())
            #expect(events.count == 2)
            #expect(events.allSatisfy { $0.origin == .auto && $0.dayKey == yesterday.key })
        }

        @Test func aLaterRunForTheDayReplacesItsReadings() async throws {
            let store = try makeStore()
            let instagram = insertLinked(
                "Under 1h Instagram",
                ItemLink(metric: .screenTime, subject: "Instagram", rule: .atMost(3600), unit: .seconds),
                into: store
            )
            let intent = LogScreenTimeIntent()
            intent.store = store
            intent.day = day(10, 20).startDate()
            intent.apps = "Instagram (50m)\nSafari (5m)"
            _ = try await intent.perform()
            #expect(try isDone(instagram, on: day(10, 20), in: store))

            intent.apps = #"[{"app": "Instagram", "duration": 4000}]"#
            _ = try await intent.perform()
            #expect(try readings(in: store).map(\.subject) == ["Instagram"])
            #expect(try !isDone(instagram, on: day(10, 20), in: store))
        }

        @Test func nothingReadablePerformsNothing() async throws {
            let store = try makeStore()
            let intent = LogScreenTimeIntent()
            intent.store = store
            intent.apps = "Instagram (50m)"
            _ = try await intent.perform()

            intent.apps = #"[{"app": "Instagram"}]"#
            await #expect(throws: LogScreenTimeError.self) { try await intent.perform() }
            // Nothing at all (today, just after midnight) isn't an error.
            intent.apps = nil
            intent.websites = ""
            _ = try await intent.perform()
            #expect(try readings(in: store).map(\.value) == [3000])
        }

        @Test func todaysRunsTrackProgressWithoutClosingLimits() async throws {
            let store = try makeStore()
            let instagram = insertLinked(
                "Under 1h Instagram",
                ItemLink(metric: .screenTime, subject: "Instagram", rule: .atMost(3600), unit: .seconds,
                         accumulates: true),
                into: store
            )
            let kindle = insertLinked(
                "Read 30m on Kindle",
                ItemLink(metric: .screenTime, subject: "Kindle", rule: .atLeast(1800), unit: .seconds,
                         accumulates: true),
                into: store
            )
            let intent = LogScreenTimeIntent()
            intent.store = store
            intent.day = store.clock.now()
            intent.apps = "Instagram (35m)\nKindle (10m)"
            _ = try await intent.perform()
            #expect(try !isDone(instagram, on: fixedToday, in: store))
            #expect(try !isDone(kindle, on: fixedToday, in: store))
            let todays = try readings(in: store)
            #expect(todays.allSatisfy { $0.day == fixedToday })
            let entry = DayPlanner().entry(for: instagram.plan, on: fixedToday, ledger: CompletionLedger([]))
            #expect(entry?.readingLabel(from: todays, on: fixedToday) == "35m of 1h")

            intent.apps = "Instagram (50m)\nKindle (31m)"
            _ = try await intent.perform()
            #expect(try !isDone(instagram, on: fixedToday, in: store))
            #expect(try isDone(kindle, on: fixedToday, in: store))
        }

        @Test func summary() {
            let report = ScreenTimeReport(apps: "Notes (1m)\nbad", websites: "apple.com (2m)\nx.com (1m)")
            #expect(LogScreenTimeIntent.summary(of: report, on: yesterday)
                == "2026-10-29: 1 app, 2 websites, 1 unreadable row")
            #expect(LogScreenTimeIntent.summary(of: ScreenTimeReport(apps: "Notes (1m)"), on: yesterday)
                == "2026-10-29: 1 app, 0 websites")
        }
    }
#endif
