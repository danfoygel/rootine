import Foundation
import SwiftData
import Testing

private let calendar = mondayFirstCalendar

/// A moment on a day of the fixed week, in the suites' Los Angeles calendar.
private func at(_ hour: Int, _ minute: Int = 0, second: Int = 0, on day: LocalDay = fixedToday) -> Date {
    calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour,
                                       minute: minute, second: second)) ?? .distantPast
}

private func event(
    _ start: Date,
    _ flags: MotionKind...,
    confidence: MotionEvent.Confidence = .high
) -> MotionEvent {
    MotionEvent(
        start: start,
        stationary: flags.contains(.stationary),
        walking: flags.contains(.walking),
        running: flags.contains(.running),
        automotive: flags.contains(.automotive),
        cycling: flags.contains(.cycling),
        unknown: flags.contains(.unknown),
        confidence: confidence
    )
}

private let summariser = MotionSummariser(calendar: calendar)

/// Merged segments as (kind, minutes), for compact expectations.
private func shape(_ segments: [MotionSegment]) -> [String] {
    segments.map { "\($0.kind.rawValue) \(Int(($0.duration / 60).rounded()))" }
}

private func segments(_ events: [MotionEvent], now: Date = at(23)) -> [String] {
    shape(summariser.segments(events, now: now))
}

struct MotionLabelTests {
    @Test func oneFlagGivesItsKind() {
        for kind in MotionKind.allCases {
            #expect(MotionSummariser.kind(of: event(at(9), kind)) == kind)
        }
    }

    @Test func severalFlagsPickByPriority() {
        // Driving beats stationary at a red light; the rest follow automotive > cycling > running > walking.
        #expect(MotionSummariser.kind(of: event(at(9), .automotive, .stationary)) == .automotive)
        #expect(MotionSummariser.kind(of: event(at(9), .walking, .cycling, .automotive)) == .automotive)
        #expect(MotionSummariser.kind(of: event(at(9), .walking, .cycling)) == .cycling)
        #expect(MotionSummariser.kind(of: event(at(9), .walking, .running)) == .running)
        #expect(MotionSummariser.kind(of: event(at(9), .stationary, .walking)) == .walking)
        #expect(MotionSummariser.kind(of: event(at(9), .unknown, .stationary)) == .stationary)
    }

    @Test func noFlagsIsUnknown() {
        #expect(MotionSummariser.kind(of: event(at(9))) == .unknown)
    }

    @Test func lowConfidenceIsUnknown() {
        #expect(MotionSummariser.kind(of: event(at(9), .automotive, confidence: .low)) == .unknown)
        #expect(MotionSummariser.kind(of: event(at(9), .walking, confidence: .medium)) == .walking)
    }
}

struct MotionSegmentTests {
    @Test func eachSegmentEndsAtTheNextEvent() {
        let events = [event(at(9), .walking), event(at(9, 20), .stationary), event(at(10), .automotive)]
        #expect(segments(events, now: at(10, 30)) == ["walking 20", "stationary 40", "automotive 30"])
    }

    @Test func eventsAreSortedFirst() {
        let events = [event(at(10), .stationary), event(at(9), .walking)]
        #expect(segments(events, now: at(11)) == ["walking 60", "stationary 60"])
    }

    @Test func longSilencesAreCappedAsMissingData() {
        // Phone off from 10:00 until 18:00: the walk is capped at three hours, not stretched to eight.
        let events = [event(at(10), .walking), event(at(18), .stationary)]
        #expect(segments(events, now: at(19)) == ["walking 180", "stationary 60"])
    }

    @Test func theLastSegmentRunsUntilNow() {
        #expect(segments([event(at(9), .walking)], now: at(9, 25)) == ["walking 25"])
    }

    @Test func neighboursOfTheSameKindMerge() {
        // CoreMotion repeats a label when only its confidence changes.
        let events = [event(at(9), .walking), event(at(9, 10), .walking, confidence: .medium),
                      event(at(9, 30), .stationary)]
        #expect(segments(events, now: at(10)) == ["walking 30", "stationary 30"])
    }

    @Test func aShortBlipBetweenTheSameKindIsAbsorbed() {
        // A 1-minute stop at a light, then a 90-second low-confidence patch, inside one drive.
        let events = [
            event(at(8), .automotive),
            event(at(8, 10), .automotive, .stationary, confidence: .low),
            event(at(8, 11), .automotive),
            event(at(8, 20), .stationary),
            event(at(8, 21, second: 30), .automotive),
            event(at(8, 40), .walking),
        ]
        #expect(segments(events, now: at(8, 50)) == ["automotive 40", "walking 10"])
    }

    @Test func aRunOfBlipsUnderTwoMinutesIsAbsorbed() {
        let events = [event(at(9), .walking), event(at(9, 10), .stationary),
                      event(at(9, 10, second: 50), .unknown), event(at(9, 11, second: 40), .walking),
                      event(at(9, 30), .stationary)]
        #expect(segments(events, now: at(10)) == ["walking 30", "stationary 30"])
    }

    @Test func longerStopsAndBlipsBetweenDifferentKindsStay() {
        // A 3-minute stop splits the walk; a short stop between a walk and a drive isn't absorbed into either.
        let events = [event(at(9), .walking), event(at(9, 10), .stationary), event(at(9, 13), .walking),
                      event(at(9, 20), .stationary), event(at(9, 21), .automotive), event(at(9, 40), .stationary)]
        #expect(segments(events, now: at(10)) == [
            "walking 10", "stationary 3", "walking 7", "stationary 1", "automotive 19", "stationary 20",
        ])
    }

    @Test func blipsAreNotAbsorbedAcrossMissingData() {
        // The walk before the gap is capped, so the walk after it is a new segment.
        let events = [event(at(6), .walking), event(at(12), .walking)]
        #expect(segments(events, now: at(12, 30)) == ["walking 180", "walking 30"])
    }

    @Test func shortSegmentsAreDroppedByKind() {
        // Walking needs a minute, driving and cycling three; stationary and unknown are kept whatever their length.
        let events = [
            event(at(9), .walking), event(at(9, 0, second: 50), .stationary),
            event(at(9, 10), .automotive), event(at(9, 12), .stationary),
            event(at(9, 20), .cycling), event(at(9, 22, second: 30), .unknown),
            event(at(9, 23), .walking), event(at(9, 24), .stationary),
        ]
        #expect(segments(events, now: at(9, 30)) == [
            "stationary 9", "stationary 8", "unknown 1", "walking 1", "stationary 6",
        ])
    }
}

struct MotionDaySummaryTests {
    @Test func minutesAddUpPerKind() throws {
        let events = [event(at(8), .walking), event(at(8, 15), .automotive), event(at(8, 45), .stationary),
                      event(at(17), .walking), event(at(17, 20), .running), event(at(17, 30), .stationary)]
        let days = summariser.summarise(events, from: at(0), now: at(20))
        let today = try #require(days.first)
        #expect(days.count == 1)
        #expect(today.day == fixedToday)
        #expect(today.minutes[.walking] == 35)
        #expect(today.minutes[.running] == 10)
        #expect(today.minutes[.automotive] == 30)
        #expect(today.minutes[.cycling] == 0)
        #expect(today.isComplete == false)
    }

    @Test func segmentsAreSplitAtMidnight() {
        let yesterday = fixedToday.adding(days: -1)
        let events = [event(at(23, 50, on: yesterday), .automotive), event(at(0, 20), .stationary)]
        let days = summariser.summarise(events, from: at(0, on: yesterday), now: at(2))
        #expect(days.map(\.day) == [yesterday, fixedToday])
        #expect(days[0].minutes[.automotive] == 10)
        #expect(days[1].minutes[.automotive] == 20)
        #expect(days[1].minutes[.stationary] == 100)
        #expect(days[0].segments.last?.end == at(0))
    }

    @Test func aDriveAcrossMidnightIsMergedBeforeTheSplit() {
        // Two minutes either side of midnight: too short on its own, but one four-minute drive.
        let yesterday = fixedToday.adding(days: -1)
        let events = [event(at(23, 58, on: yesterday), .automotive), event(at(0, 2), .stationary)]
        let days = summariser.summarise(events, from: at(0, on: yesterday), now: at(1))
        #expect(days.map { $0.minutes[.automotive] } == [2, 2])
    }

    @Test func daysBeforeTheStartAreLeftOutAndTheLeadIsClipped() {
        // The query starts an hour before midnight to catch the activity under way; that hour isn't summarised.
        let events = [event(at(23, 30, on: fixedToday.adding(days: -1)), .stationary), event(at(1), .walking)]
        let days = summariser.summarise(events, from: at(0), now: at(1, 30))
        #expect(days.map(\.day) == [fixedToday])
        #expect(days.first?.minutes[.stationary] == 60)
        #expect(days.first?.minutes[.walking] == 30)
    }

    @Test func aDayIsCompleteAnHourAfterItEnds() {
        let yesterday = fixedToday.adding(days: -1)
        let events = [event(at(12, on: yesterday), .stationary)]
        let early = summariser.summarise(events, from: at(0, on: yesterday), now: at(0, 59))
        let late = summariser.summarise(events, from: at(0, on: yesterday), now: at(1))
        #expect(early.map(\.isComplete) == [false, false])
        #expect(late.map(\.isComplete) == [true, false])
    }

    @Test func noEventsMeansNoReadings() {
        let days = summariser.summarise([], from: at(0, on: fixedToday.adding(days: -1)), now: at(9))
        #expect(days.count == 2)
        #expect(days.allSatisfy { $0.readings().isEmpty })
    }

    @Test func completeDaysStoreEveryKindIncludingZeros() throws {
        let yesterday = fixedToday.adding(days: -1)
        let events = [event(at(8, on: yesterday), .walking), event(at(8, 20, on: yesterday), .running),
                      event(at(8, 30, on: yesterday), .stationary)]
        let day = try #require(summariser.summarise(events, from: at(0, on: yesterday), now: at(9)).first)
        let readings = Dictionary(uniqueKeysWithValues: day.readings().map { ($0.metric, $0) })
        #expect(readings[.walkingMinutes]?.value == 20)
        #expect(readings[.runningMinutes]?.value == 10)
        #expect(readings[.onFootMinutes]?.value == 30)
        #expect(readings[.automotiveMinutes]?.value == 0)
        #expect(readings[.cyclingMinutes]?.value == 0)
        #expect(readings.count == 6)
        #expect(day.readings().allSatisfy { $0.source == .motion && $0.day == yesterday && $0.end == at(0) })
    }

    @Test func incompleteDaysLeaveOutZeros() throws {
        let events = [event(at(8), .walking), event(at(8, 20), .stationary)]
        let day = try #require(summariser.summarise(events, from: at(0), now: at(9)).first)
        let metrics = Set(day.readings().map(\.metric))
        #expect(metrics == [.walkingMinutes, .stationaryMinutes, .onFootMinutes])
        #expect(day.readings().allSatisfy { $0.end == nil })
    }
}

struct MotionImportWindowTests {
    @Test func firstImportStartsAtTheOldestWholeDay() {
        // Seven days back from 09:00 is 09:00 on the 23rd; the first whole day with an hour's lead is the 24th.
        let first = MotionImportWindow.firstDay(resumingFrom: nil, now: at(9), calendar: calendar)
        #expect(first == at(0, on: day(10, 24)))
        // At 22:30 the 24th's lead (from 23:00 on the 23rd) is still inside the seven days; at 23:30 it isn't.
        #expect(MotionImportWindow.firstDay(resumingFrom: nil, now: at(22, 30), calendar: calendar)
            == at(0, on: day(10, 24)))
        #expect(MotionImportWindow.firstDay(resumingFrom: nil, now: at(23, 30), calendar: calendar)
            == at(0, on: day(10, 25)))
        #expect(MotionImportWindow.firstDay(resumingFrom: nil, now: at(0, 30), calendar: calendar)
            == at(0, on: day(10, 24)))
    }

    @Test func laterImportsResumeFromTheFirstIncompleteDay() {
        let resume = at(0, on: fixedToday.adding(days: -1))
        #expect(MotionImportWindow.firstDay(resumingFrom: resume, now: at(9), calendar: calendar) == resume)
        // Not opened for two weeks: clamped to what CoreMotion still has.
        #expect(MotionImportWindow.firstDay(resumingFrom: at(0, on: day(10, 10)), now: at(9), calendar: calendar)
            == at(0, on: day(10, 24)))
    }

    @Test func resumeIsTheFirstDayNotComplete() {
        let events = [event(at(12, on: fixedToday.adding(days: -2)), .stationary)]
        let early = summariser.summarise(events, from: at(0, on: fixedToday.adding(days: -2)), now: at(0, 30))
        #expect(MotionImportWindow.resume(after: early) == at(0, on: fixedToday.adding(days: -1)))
        #expect(MotionImportWindow.resume(after: []) == nil)
    }
}

struct MotionLinkTests {
    @Test func everyActivityMapsToItsOwnMetric() {
        for activity in MotionActivity.allCases {
            #expect(MotionActivity(metric: activity.metric) == activity)
            #expect(activity.link(.atLeast(20)).isMotion)
        }
        #expect(Set(MotionActivity.allCases.map(\.metric)).count == MotionActivity.allCases.count)
        #expect(MotionActivity.driving.metric == .automotiveMinutes)
        #expect(ItemLink(metric: ReadingMetric(rawValue: "screenTime"), rule: .atMost(60)).isMotion == false)
    }

    @Test func linksShowMinutes() {
        #expect(MotionActivity.onFoot.link(.atLeast(20)).label(for: 14) == "14 min of 20 min")
    }
}

@MainActor
struct MotionStoreTests {
    @Test func reimportingADayIsHarmless() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let walk = Item(name: "Walk 20 min", kind: .habit, startDay: day(10, 1))
        walk.link = ItemLink(metric: .onFootMinutes, rule: .atLeast(20), unit: .suffix("min"))
        let noDriving = Item(name: "No driving", kind: .habit, startDay: day(10, 1))
        noDriving.link = ItemLink(metric: .automotiveMinutes, rule: .atMost(0), unit: .suffix("min"))
        context.insert(walk)
        context.insert(noDriving)

        func importDay(now: Date) throws -> [CompletionRecord] {
            let events = [event(at(8), .walking), event(at(8, 15), .running), event(at(8, 25), .stationary)]
            return try summariser.summarise(events, from: at(0), now: now).flatMap {
                try context.replaceReadings($0.readings(), from: .motion, on: $0.day)
            }
        }

        // During the day: the walk completes, but the driving limit waits for the finished day.
        let first = try importDay(now: at(9))
        #expect(first.map(\.itemID) == [walk.id])
        #expect(try importDay(now: at(10)).isEmpty)
        // The next morning the day is complete, with zero driving minutes.
        let next = try importDay(now: at(9, on: fixedToday.adding(days: 1)))
        #expect(next.map(\.itemID) == [noDriving.id])
        #expect(try importDay(now: at(10, on: fixedToday.adding(days: 1))).isEmpty)
        let auto = try context.fetch(FetchDescriptor<CompletionEvent>()).filter { $0.origin == .auto }
        #expect(auto.count == 2)
    }
}
