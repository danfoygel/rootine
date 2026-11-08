import Foundation
import SwiftData
import Testing

// HealthKit's pure layer (DATA.md phase 2): per-type aggregation, day assignment and editor choices. Samples are
// built in code; nothing here touches HealthKit.

private let calendar = mondayFirstCalendar

private func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0, second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute,
                                       second: second)) ?? .now
}

/// A sample from `start` lasting `minutes` (0 for a point sample).
private func sample(_ start: Date, minutes: Double = 0, _ value: Double = 0, subject: String = "") -> HealthSample {
    HealthSample(start: start, end: start.addingTimeInterval(minutes * 60), value: value, subject: subject)
}

/// The readings for `day` by metric.
private func readings(
    _ type: HealthType,
    _ samples: [HealthSample],
    on day: LocalDay = fixedToday
) -> [ReadingMetric: Double] {
    Dictionary(HealthAggregator.readings(type, from: samples, on: day, calendar: calendar)
        .map { ($0.metric, $0.value) }) { first, _ in first }
}

struct HealthAggregationTests {
    private let yesterday = fixedToday.adding(days: -1)

    @Test(arguments: [HealthType.steps, .distance, .exercise, .water, .daylight])
    func sumTypesAddUpTheDay(_ type: HealthType) throws {
        let samples = [sample(at(fixedToday, 8), minutes: 10, 1200), sample(at(fixedToday, 17), minutes: 5, 300)]
        let result = HealthAggregator.readings(type, from: samples, on: fixedToday, calendar: calendar)
        let reading = try #require(result.first)
        #expect(result.count == 1)
        #expect(reading.metric == type.metrics[0])
        #expect(reading.source == type.source)
        #expect(reading.day == fixedToday)
        #expect(reading.value == 1500)
        #expect(reading.start == at(fixedToday, 8))
        #expect(reading.end == at(fixedToday, 17, 5))
    }

    @Test(arguments: HealthType.allCases)
    func emptyDayHasNoReadings(_ type: HealthType) {
        #expect(HealthAggregator.readings(type, from: [], on: fixedToday, calendar: calendar).isEmpty)
        // Samples for another day don't make one.
        let elsewhere = [sample(at(fixedToday.adding(days: -3), 12), minutes: 30, 0.95)]
        #expect(HealthAggregator.readings(type, from: elsewhere, on: fixedToday, calendar: calendar).isEmpty)
    }

    @Test(arguments: HealthType.allCases)
    func exactDuplicatesCountOnce(_ type: HealthType) {
        // ViHealth re-syncing writes the same values and times again under new sample IDs.
        let night = [
            sample(at(yesterday, 23), minutes: 30, 0.93, subject: "Running"),
            sample(at(fixedToday, 2), minutes: 60, 0.88, subject: "Running"),
            sample(at(fixedToday, 9), minutes: 20, 0.97, subject: "Yoga"),
        ]
        #expect(readings(type, night + night + night) == readings(type, night))
    }

    @Test func calendarTypesSplitAtMidnight() {
        let lateSteps = sample(at(yesterday, 23, 59), minutes: 1, 40)
        let earlySteps = sample(at(fixedToday, 0, 1), minutes: 1, 25)
        #expect(readings(.steps, [lateSteps, earlySteps]) == [.steps: 25])
        #expect(readings(.steps, [lateSteps, earlySteps], on: yesterday) == [.steps: 40])
        // A mindful session that runs past midnight counts toward the day it started.
        let session = sample(at(yesterday, 23, 50), minutes: 20)
        #expect(readings(.mindfulness, [session], on: yesterday) == [.mindfulTime: 1200])
        #expect(readings(.mindfulness, [session]).isEmpty)
    }

    @Test func countTypesCountDistinctSamples() {
        let pressure = [
            sample(at(fixedToday, 7, 30), 128),
            sample(at(fixedToday, 7, 32), 124),
            sample(at(fixedToday, 21), 131),
        ]
        #expect(readings(.bloodPressure, pressure) == [.bloodPressureReadings: 3])
        let stood = (8 ... 19).map { sample(at(fixedToday, $0), minutes: 60) }
        #expect(readings(.stand, stood + stood.prefix(3)) == [.standHours: 12])
    }

    @Test func workoutsCountPerActivity() {
        let workouts = [
            sample(at(fixedToday, 7), minutes: 30, 1800, subject: "Running"),
            sample(at(fixedToday, 12), minutes: 45, 2700, subject: "Strength"),
            sample(at(fixedToday, 18), minutes: 20, 1200, subject: "Running"),
        ]
        let result = HealthAggregator.readings(.workouts, from: workouts, on: fixedToday, calendar: calendar)
        #expect(result.map(\.subject) == ["Running", "Strength"])
        #expect(result.map(\.value) == [2, 1])
        // "Any workout" links take every subject; one activity takes its own.
        #expect(ItemLink(metric: .workouts, rule: .atLeast(1)).value(from: result) == 3)
        #expect(ItemLink(metric: .workouts, subject: "Running", rule: .atLeast(1)).value(from: result) == 2)
    }

    @Test func sleepIsTimeAsleepWithOverlapsCountedOnce() {
        // The Watch and a sleep app both record the same night; the gap 01:00–01:30 is awake.
        let watch = [sample(at(yesterday, 23), minutes: 120), sample(at(fixedToday, 1, 30), minutes: 300)]
        let app = [sample(at(yesterday, 23, 30), minutes: 60), sample(at(fixedToday, 5), minutes: 120)]
        #expect(readings(.sleep, watch + app) == [.timeAsleep: (120.0 + 330) * 60])
    }

    @Test func aNightBelongsToTheDayItEnds() {
        let evening = sample(at(yesterday, 22), minutes: 90)
        let morning = sample(at(fixedToday, 0, 15), minutes: 400)
        let nap = sample(at(fixedToday, 14), minutes: 30)
        let nextEvening = sample(at(fixedToday, 18), minutes: 60)
        let all = [evening, morning, nap, nextEvening]
        #expect(readings(.sleep, all) == [.timeAsleep: (90.0 + 400 + 30) * 60])
        #expect(readings(.sleep, all, on: fixedToday.adding(days: 1)) == [.timeAsleep: 3600])
        #expect(readings(.sleep, all, on: yesterday).isEmpty)
        // The same cut-off applies to overnight SpO2, and not to heart rate.
        let spo2 = [sample(at(yesterday, 23), 0.95), sample(at(fixedToday, 3), 0.91)]
        #expect(readings(.oxygenSaturation, spo2)[.oxygenMinimum] == 0.91)
        #expect(readings(.heartRate, [sample(at(yesterday, 23), 52)]).isEmpty)
    }

    @Test func overnightOxygenSummary() throws {
        // One point sample a minute, as a ring recording arrives.
        let values = [0.95, 0.89, 0.87, 0.93, 0.94]
        let night = values.enumerated().map { sample(at(fixedToday, 2, $0.offset), $0.element) }
        let result = readings(.oxygenSaturation, night)
        #expect(result[.oxygenMinimum] == 0.87)
        #expect(try abs(#require(result[.oxygenAverage]) - 0.916) < 0.0001)
        #expect(result[.oxygenBelow90] == 120)
        // Re-synced copies of the night don't change it.
        #expect(readings(.oxygenSaturation, night + night) == result)
    }

    @Test func oxygenTimeBelowUsesSpansAndCapsGaps() {
        let samples = [
            // Hourly summaries with their own span count for their span.
            sample(at(fixedToday, 1), minutes: 60, 0.88),
            // A lone low point sample an hour before the next counts for the cap, not the hour.
            sample(at(fixedToday, 3), 0.85),
            sample(at(fixedToday, 4), 0.96),
            // The last point sample has no next one and counts for nothing.
            sample(at(fixedToday, 5), 0.80),
        ]
        #expect(readings(.oxygenSaturation, samples)[.oxygenBelow90] == 3600 + HealthAggregator.maxSampleGap)
    }

    @Test func heartRateRange() {
        let samples = [sample(at(fixedToday, 6), 58), sample(at(fixedToday, 12), 92), sample(at(fixedToday, 18), 71)]
        #expect(readings(.heartRate, samples) == [.heartRateMinimum: 58, .heartRateAverage: 221.0 / 3,
                                                  .heartRateMaximum: 92])
    }

    @Test func windows() {
        let calendarDay = HealthType.steps.window(for: fixedToday, calendar: calendar)
        #expect(calendarDay.start == at(fixedToday, 0))
        #expect(calendarDay.end == at(fixedToday.adding(days: 1), 0))
        let night = HealthType.sleep.window(for: fixedToday, calendar: calendar)
        #expect(night.start == at(yesterday, 18))
        #expect(night.end == at(fixedToday, 18))
        // Sunday 2026-11-01 is 25 hours long in Los Angeles; the night ending on it is too.
        let dstNight = HealthType.oxygenSaturation.window(for: day(11, 2), calendar: calendar)
        #expect(dstNight.duration == 24 * 3600)
        #expect(HealthType.oxygenSaturation.window(for: day(11, 1), calendar: calendar).duration == 25 * 3600)
        #expect(HealthType.steps.window(for: day(11, 1), calendar: calendar).duration == 25 * 3600)
    }

    @Test func samplesInAWindowBelongToItsDay() {
        // Whatever the shell fetches for a day's window aggregates to that day.
        for type in HealthType.allCases {
            let window = type.window(for: fixedToday, calendar: calendar)
            let edges = [sample(window.start), sample(window.end.addingTimeInterval(-1))]
            #expect(edges.allSatisfy { type.day(of: $0, calendar: calendar) == fixedToday })
            #expect(type.day(of: sample(window.end), calendar: calendar) == fixedToday.adding(days: 1))
        }
    }
}

struct HealthDaysTests {
    @Test func affectedDaysIncludeTodayAndStayInTheLookback() {
        let samples = [
            sample(at(fixedToday.adding(days: -2), 9)),
            sample(at(fixedToday.adding(days: -2), 15)),
            sample(at(fixedToday.adding(days: -30), 9)),
        ]
        let days = HealthAggregator.affectedDays(.steps, by: samples, today: fixedToday, lookback: 7,
                                                 calendar: calendar)
        #expect(days == [fixedToday.adding(days: -2), fixedToday])
        #expect(HealthAggregator.affectedDays(.steps, by: [], today: fixedToday, lookback: 7, calendar: calendar)
            == [fixedToday])
    }

    @Test func tonightsEveningSamplesAreNotFutureDays() {
        // Sleep starting at 22:00 today belongs to tomorrow, which isn't refreshed until it's today.
        let tonight = sample(at(fixedToday, 22), minutes: 30)
        #expect(HealthAggregator.affectedDays(.sleep, by: [tonight], today: fixedToday, lookback: 7,
                                              calendar: calendar) == [fixedToday])
    }

    @Test func unchangedReadingsAreRecognised() {
        let night = [sample(at(fixedToday, 2), 0.9), sample(at(fixedToday, 3), 0.95)]
        let first = HealthAggregator.readings(.oxygenSaturation, from: night, on: fixedToday, calendar: calendar)
        let again = HealthAggregator.readings(.oxygenSaturation, from: night, on: fixedToday, calendar: calendar)
        #expect(first.map(\.id) != again.map(\.id))
        #expect(HealthAggregator.isUnchanged(first, again))
        #expect(HealthAggregator.isUnchanged([], []))
        let more = HealthAggregator.readings(.oxygenSaturation, from: night + [sample(at(fixedToday, 4), 0.85)],
                                             on: fixedToday, calendar: calendar)
        #expect(!HealthAggregator.isUnchanged(first, more))
        #expect(!HealthAggregator.isUnchanged(first, []))
    }
}

struct HealthTypeTests {
    @Test func everyMetricMapsBackToItsType() {
        for type in HealthType.allCases {
            for metric in type.metrics {
                #expect(HealthType(metric: metric) == type)
            }
        }
        #expect(HealthType(metric: ReadingMetric(rawValue: "screenTime")) == nil)
    }

    @Test func metricsAndSourcesAreDistinct() {
        let metrics = HealthType.allCases.flatMap(\.metrics)
        #expect(Set(metrics).count == metrics.count)
        #expect(Set(HealthType.allCases.map(\.source)).count == HealthType.allCases.count)
    }

    @Test func everyMetricHasAnEditorChoice() {
        #expect(Set(HealthChoice.all.map(\.metric)) == Set(HealthType.allCases.flatMap(\.metrics)))
        #expect(HealthChoice.all.allSatisfy { $0.type != nil && $0.defaultAmount > 0 })
    }
}

struct HealthChoiceTests {
    private func choice(_ metric: ReadingMetric) throws -> HealthChoice {
        try #require(HealthChoice.choice(for: metric))
    }

    @Test func amountsConvertToReadingUnits() throws {
        #expect(try choice(.steps).link(.atLeast, amount: 10000).rule == .atLeast(10000))
        #expect(try choice(.timeInDaylight).link(.atLeast, amount: 20).rule == .atLeast(1200))
        #expect(try choice(.timeAsleep).link(.atLeast, amount: 7.5).rule == .atLeast(27000))
        #expect(try choice(.oxygenMinimum).link(.atLeast, amount: 90).rule == .atLeast(0.9))
        #expect(try choice(.water).link(.counts, amount: 1).rule == .counts(per: 1))
        #expect(try choice(.workouts).link(.atLeast, amount: 1, subject: "Yoga").subject == "Yoga")
    }

    @Test func entryRoundTrips() {
        for choice in HealthChoice.all {
            for rule in HealthChoice.Rule.allCases {
                let entry = choice.entry(for: choice.link(rule, amount: 42))
                #expect(entry.rule == rule)
                #expect(abs(entry.amount - 42) < 0.000001)
            }
        }
    }

    @Test func defaultRules() throws {
        #expect(try choice(.steps).defaultRule(for: .habit) == .atLeast)
        #expect(try choice(.oxygenBelow90).defaultRule(for: .habit) == .atMost)
        #expect(try choice(.water).defaultRule(for: .counted) == .counts)
    }

    @Test func labelsShowReadingsInTheirUnits() throws {
        #expect(try choice(.timeInDaylight).link(.atLeast, amount: 20).label(for: 900) == "15m of 20m")
        #expect(try choice(.timeAsleep).link(.atLeast, amount: 7).label(for: 6.5 * 3600) == "6h 30m of 7h")
        #expect(try choice(.oxygenMinimum).link(.atLeast, amount: 90).label(for: 0.87) == "87% of 90%")
    }
}

@MainActor
struct HealthStoreTests {
    @Test func aggregatedReadingsCompleteLinkedItems() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let steps = Item(name: "Walk", kind: .habit, startDay: day(10, 1))
        steps.link = try #require(HealthChoice.choice(for: .steps)).link(.atLeast, amount: 10000)
        let water = Item(name: "Water", kind: .counted, startDay: day(10, 1))
        water.dailyTarget = 2000
        water.link = try #require(HealthChoice.choice(for: .water)).link(.counts, amount: 1)
        let takeBP = Item(name: "Take BP", kind: .habit, startDay: day(10, 1))
        takeBP.link = try #require(HealthChoice.choice(for: .bloodPressureReadings)).link(.atLeast, amount: 1)
        for item in [steps, water, takeBP] {
            context.insert(item)
        }

        func apply(_ type: HealthType, _ samples: [HealthSample]) throws -> [CompletionRecord] {
            let readings = HealthAggregator.readings(type, from: samples, on: fixedToday, calendar: calendar)
            return try context.replaceReadings(readings, from: type.source, on: fixedToday)
        }
        #expect(try apply(.steps, [sample(at(fixedToday, 9), minutes: 60, 6200)]).isEmpty)
        #expect(try apply(.water, [sample(at(fixedToday, 9), 250), sample(at(fixedToday, 11), 500)])
            .map(\.amount) == [750])
        #expect(try apply(.bloodPressure, [sample(at(fixedToday, 7), 125)]).map(\.amount) == [1])
        // A later wake with more steps completes the walk; re-reading the BP day changes nothing.
        #expect(try apply(.steps, [sample(at(fixedToday, 9), minutes: 600, 10400)]).map(\.itemID) == [steps.id])
        #expect(try apply(.bloodPressure, [sample(at(fixedToday, 7), 125), sample(at(fixedToday, 7), 125)])
            .isEmpty)
        // Each type replaces only its own readings.
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 3)
    }
}
