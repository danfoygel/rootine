import Foundation
import SwiftData
import Testing

// Wake and bed times from Shortcuts automations (DATA.md §5). Rules run in New York, so DST days are real.

private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar
}()

private func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0, calendar: Calendar = newYork) -> Date {
    ClockTime(hour: hour, minute: minute).date(on: day, calendar: calendar)
}

/// A moment given in UTC, for the hour that happens twice when the clocks go back.
private func utc(_ month: Int, _ dayOfMonth: Int, _ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: hour, minute: minute))
        ?? .distantPast
}

private typealias Event = DayBoundary.Event

private func event(_ kind: DayBoundary.Kind, _ trigger: DayBoundary.Trigger = .alarm, at date: Date) -> Event {
    Event(kind: kind, trigger: trigger, date: date)
}

private extension DayBoundary.Outcome {
    var reading: ReadingValue? {
        if case let .record(reading) = self {
            reading
        } else {
            nil
        }
    }

    var ignored: DayBoundary.Ignored? {
        if case let .ignored(reason, _) = self {
            reason
        } else {
            nil
        }
    }
}

/// Runs events through the rules in order, keeping what they record, like the intent does.
private func log(_ events: [Event]) -> (readings: [ReadingValue], outcomes: [DayBoundary.Outcome]) {
    var readings: [ReadingValue] = []
    var outcomes: [DayBoundary.Outcome] = []
    for event in events {
        let outcome = DayBoundary.outcome(of: event, existing: readings, calendar: newYork)
        if let reading = outcome.reading {
            readings.append(reading)
        }
        outcomes.append(outcome)
    }
    return (readings, outcomes)
}

private let upBySeven = ItemLink(metric: .wakeTime, rule: .atMost(420), combine: .min, unit: .clockTime)

struct DayBoundaryRuleTests {
    @Test func wakeIsMinutesSinceMidnightOnItsDay() throws {
        let reading = try #require(DayBoundary.outcome(of: event(.wake, at: at(day(11, 7), 6, 42)), existing: [],
                                                       calendar: newYork).reading)
        #expect(reading.source == .dayBoundary)
        #expect(reading.metric == .wakeTime)
        #expect(reading.subject == "alarm")
        #expect(reading.day == day(11, 7))
        #expect(reading.value == 402)
        #expect(reading.start == at(day(11, 7), 6, 42))
    }

    @Test func firstWakeWins() {
        let (readings, outcomes) = log([
            event(.wake, .focus, at: at(day(11, 7), 6, 40)),
            event(.wake, .alarm, at: at(day(11, 7), 6, 42)),
            // An automation that runs late with an earlier time still counts; `combine: .min` picks it.
            event(.wake, .alarm, at: at(day(11, 7), 6, 30)),
            event(.wake, .alarm, at: at(day(11, 7), 6, 30)),
        ])
        #expect(readings.map(\.value) == [400, 390])
        #expect(outcomes[1].ignored == .notFirstWake(400))
        #expect(outcomes[3].ignored == .notFirstWake(390))
        #expect(upBySeven.value(from: readings) == 390)
    }

    @Test func eachDayHasItsOwnFirstWake() {
        let (readings, _) = log([
            event(.wake, at: at(day(11, 7), 6, 42)),
            event(.wake, at: at(day(11, 8), 8, 15)),
        ])
        #expect(readings.map(\.day) == [day(11, 7), day(11, 8)])
        #expect(readings.map(\.value) == [402, 495])
    }

    @Test func nightWakingIsNotTheStartOfTheDay() {
        let (readings, outcomes) = log([
            event(.wake, .focus, at: at(day(11, 7), 2, 10)),
            event(.wake, .alarm, at: at(day(11, 7), 6, 42)),
        ])
        #expect(outcomes[0].ignored == .night)
        #expect(readings.map(\.value) == [402])
        // From 3:00 it is a wake time (an early flight).
        #expect(DayBoundary.outcome(of: event(.wake, at: at(day(11, 7), 3, 0)), existing: [], calendar: newYork)
            .reading?.value == 180)
    }

    @Test func napsAreIgnored() {
        let (readings, outcomes) = log([
            event(.wake, at: at(day(11, 7), 6, 42)),
            event(.bed, .focus, at: at(day(11, 7), 14, 0)),
            event(.wake, at: at(day(11, 7), 15, 30)),
            event(.bed, .focus, at: at(day(11, 7), 17, 59)),
            event(.bed, .focus, at: at(day(11, 7), 18, 0)),
        ])
        #expect(outcomes[1].ignored == .nap)
        #expect(outcomes[2].ignored == .notFirstWake(402))
        #expect(outcomes[3].ignored == .nap)
        #expect(readings.map(\.metric) == [.wakeTime, .bedTime])
        #expect(readings.map(\.value) == [402, 1080])
    }

    @Test func bedAfterMidnightBelongsToThePreviousDay() throws {
        let (readings, _) = log([
            event(.bed, .schedule, at: at(day(11, 7), 22, 30)),
            event(.bed, .focus, at: at(day(11, 8), 0, 30)),
            event(.bed, .focus, at: at(day(11, 8), 5, 59)),
        ])
        #expect(readings.map(\.day) == [day(11, 7), day(11, 7)])
        #expect(readings.map(\.value) == [1350, 1470])
        // The latest signal is the best guess at bed time; a link takes it with `combine: .max`.
        let inBedByMidnight = ItemLink(metric: .bedTime, rule: .atMost(1440), combine: .max, unit: .clockTime)
        let value = try #require(inBedByMidnight.value(from: readings))
        #expect(inBedByMidnight.label(for: value) == "0:30 of 0:00")
        #expect(inBedByMidnight.progress(for: value, target: 1) == 0)
    }

    @Test func eachTriggerLogsOneBedTimeANight() {
        let (readings, outcomes) = log([
            event(.bed, .focus, at: at(day(11, 7), 23, 0)),
            event(.bed, .focus, at: at(day(11, 7), 23, 40)),
            event(.bed, .schedule, at: at(day(11, 7), 23, 45)),
        ])
        #expect(outcomes[1].ignored == .bedAlreadyLogged(1380))
        #expect(readings.map(\.subject) == ["focus", "schedule"])
    }

    @Test func springForwardKeepsWallClockMinutes() {
        // 2026-03-08: 2:00 → 3:00 in New York. 7:00 is five hours after midnight in elapsed time.
        let (readings, _) = log([
            event(.wake, at: at(day(3, 8), 7, 0)),
            event(.bed, at: at(day(3, 8), 23, 0)),
        ])
        #expect(readings.map(\.value) == [420, 1380])
        #expect(readings.map(\.day) == [day(3, 8), day(3, 8)])
    }

    @Test func fallBackKeepsBothOneThirtiesOnTheNightBefore() {
        // 2026-11-01: 2:00 → 1:00 in New York, so 1:30 happens at 05:30 and 06:30 UTC.
        let (readings, _) = log([
            event(.bed, .focus, at: utc(11, 1, 5, 30)),
            event(.bed, .schedule, at: utc(11, 1, 6, 30)),
            event(.wake, at: at(day(11, 1), 7, 0)),
        ])
        #expect(readings.map(\.day) == [day(10, 31), day(10, 31), day(11, 1)])
        #expect(readings.map(\.value) == [1530, 1530, 420])
    }

    @Test func readingsOfOtherDaysAndMetricsDontBlock() {
        let yesterday = ReadingValue(source: .dayBoundary, metric: .wakeTime, subject: "alarm", day: day(11, 6),
                                     start: at(day(11, 6), 6, 0), value: 360)
        let bed = ReadingValue(source: .dayBoundary, metric: .bedTime, subject: "alarm", day: day(11, 7),
                               start: at(day(11, 7), 22, 0), value: 1320)
        let outcome = DayBoundary.outcome(of: event(.wake, at: at(day(11, 7), 6, 42)), existing: [yesterday, bed],
                                          calendar: newYork)
        #expect(outcome.reading?.value == 402)
    }

    @Test func candidateDaysCoverTheNightBefore() {
        #expect(DayBoundary.candidateDays(for: at(day(11, 8), 0, 30), calendar: newYork) == [day(11, 7), day(11, 8)])
    }

    @Test func summaries() {
        let recorded = DayBoundary.outcome(of: event(.wake, at: at(day(11, 7), 6, 42)), existing: [],
                                           calendar: newYork)
        #expect(recorded.summary == "Wake 6:42 logged for 2026-11-07")
        let (_, outcomes) = log([
            event(.bed, at: at(day(11, 8), 0, 30)),
            event(.bed, at: at(day(11, 8), 0, 45)),
            event(.wake, at: at(day(11, 8), 1, 0)),
            event(.bed, at: at(day(11, 8), 13, 0)),
        ])
        #expect(outcomes[0].summary == "Bed 0:30 logged for 2026-11-07")
        #expect(outcomes[1].summary == "Ignored: 2026-11-07 already has this bed time, 0:30")
        #expect(outcomes[2].summary == "Ignored: too early to be a wake time")
        #expect(outcomes[3].summary == "Ignored: too early to be a bed time")
    }
}

struct ClockTimeUnitTests {
    @Test func rowsReadAsClockTimes() {
        #expect(upBySeven.label(for: 402) == "6:42 of 7:00")
        #expect(upBySeven.format(0) == "0:00")
        #expect(upBySeven.format(1439) == "23:59")
        #expect(upBySeven.format(1470) == "0:30")
        #expect(upBySeven.summary == "wakeTime · at most 7:00")
    }

    @Test func upBySevenCompletesFromTheFirstWake() {
        #expect(upBySeven.progress(for: 402, target: 1) == 1)
        #expect(upBySeven.progress(for: 420, target: 1) == 1)
        #expect(upBySeven.progress(for: 421, target: 1) == 0)
    }

    @Test func clockTimeLinkSurvivesCodableRoundTrip() throws {
        let link = ItemLink(metric: .bedTime, subject: "focus", rule: .atMost(1410), combine: .max, unit: .clockTime)
        let decoded = try JSONDecoder().decode(ItemLink.self, from: JSONEncoder().encode(link))
        #expect(decoded == link)
    }
}

#if os(iOS)
    /// `LogDayBoundaryIntent` end to end against an in-memory store. The intent uses the current calendar.
    @MainActor
    struct LogDayBoundaryIntentTests {
        private let today = day(11, 7)

        private func makeStore(now: Date) throws -> DataStore {
            try DataStore(ephemeral: nil, relay: .inert, clock: AppClock(fixedNow: now))
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
                .sorted { $0.start < $1.start }
        }

        private func run(_ intent: LogDayBoundaryIntent, in store: DataStore) async throws -> String? {
            intent.store = store
            return try await intent.perform().value
        }

        @Test func wakeWithNoTimeUsesNowAndCompletesUpBySeven() async throws {
            let store = try makeStore(now: at(today, 6, 42, calendar: .current))
            let item = insertLinked("Up by 7:00", upBySeven, into: store)

            let summary = try await run(LogDayBoundaryIntent(kind: .wake, source: .alarm), in: store)
            #expect(summary == "Wake 6:42 logged for 2026-11-07")
            #expect(try isDone(item, on: today, in: store))
            #expect(try readings(in: store).map(\.value) == [402])
            #expect(try readings(in: store).map(\.subject) == ["alarm"])

            // A second run (the automation firing twice, or a nap alarm) changes nothing.
            let again = LogDayBoundaryIntent(kind: .wake, source: .alarm, at: at(today, 15, 0, calendar: .current))
            #expect(try await run(again, in: store) == "Ignored: 2026-11-07 already has a wake time of 6:42")
            #expect(try readings(in: store).count == 1)
            let auto = try store.container.mainContext.fetch(FetchDescriptor<CompletionEvent>())
                .filter { $0.origin == .auto }
            #expect(auto.map(\.amount) == [1])
        }

        @Test func lateWakeLeavesUpBySevenOpen() async throws {
            let store = try makeStore(now: at(today, 9, 0, calendar: .current))
            let item = insertLinked("Up by 7:00", upBySeven, into: store)
            let summary = try await run(LogDayBoundaryIntent(kind: .wake, source: .focus), in: store)
            #expect(summary == "Wake 9:00 logged for 2026-11-07")
            #expect(try !isDone(item, on: today, in: store))
        }

        @Test func bedAfterMidnightCompletesTheDayBefore() async throws {
            let store = try makeStore(now: at(today.adding(days: 1), 0, 20, calendar: .current))
            let link = ItemLink(metric: .bedTime, rule: .atMost(1470), combine: .max, unit: .clockTime)
            let item = insertLinked("In bed by 0:30", link, into: store)

            let summary = try await run(LogDayBoundaryIntent(kind: .bed, source: .focus), in: store)
            #expect(summary == "Bed 0:20 logged for 2026-11-07")
            #expect(try isDone(item, on: today, in: store))
            #expect(try !isDone(item, on: today.adding(days: 1), in: store))
            #expect(try readings(in: store).map(\.day) == [today])
        }

        @Test func napsRecordNothing() async throws {
            let store = try makeStore(now: at(today, 14, 0, calendar: .current))
            let summary = try await run(LogDayBoundaryIntent(kind: .bed, source: .focus), in: store)
            #expect(summary == "Ignored: too early to be a bed time")
            #expect(try readings(in: store).isEmpty)
        }
    }
#endif
