import Foundation

extension ReadingSource {
    /// Wake and bed times reported by Dan's Shortcuts automations (DATA.md §5).
    static let dayBoundary = ReadingSource(rawValue: "dayBoundary")
}

extension ReadingMetric {
    /// When the day started: minutes since local midnight. The earliest of the day counts.
    static let wakeTime = ReadingMetric(rawValue: "wakeTime")
    /// When the night started: minutes since the bed day's local midnight, so 00:30 the next night is 1470.
    static let bedTime = ReadingMetric(rawValue: "bedTime")
}

/// The rules that turn a wake or bed signal from a Shortcuts automation into a reading (DATA.md §5).
///
/// Times are local wall-clock times: a 7:00 wake is 420 minutes on any day, DST changes included.
enum DayBoundary {
    enum Kind: String, CaseIterable, Sendable {
        case wake
        case bed

        var metric: ReadingMetric {
            switch self {
            case .wake: .wakeTime
            case .bed: .bedTime
            }
        }
    }

    /// The automation trigger that reported the event. Stored as the reading's subject.
    enum Trigger: String, CaseIterable, Sendable {
        /// Alarm → Is Stopped: when Dan actually stopped the alarm.
        case alarm
        /// Sleep Focus turned off (wake) or on (bed).
        case focus
        /// Sleep → Bedtime starts or Waking Up: the scheduled time, not the actual one.
        case schedule
    }

    struct Event: Hashable, Sendable {
        var kind: Kind
        var trigger: Trigger
        var date: Date
    }

    /// Why an event was not recorded.
    enum Ignored: Hashable, Sendable {
        /// A wake event before `earliestWake`: up in the night, not the start of the day.
        case night
        /// A bed event between `lateBedCutoff` and `earliestBed`: a nap.
        case nap
        /// The day already has a wake time at or before this one (the value, in minutes).
        case notFirstWake(Double)
        /// This trigger already reported a bed time for the day (the value, in minutes).
        case bedAlreadyLogged(Double)
    }

    enum Outcome: Sendable {
        case record(ReadingValue)
        case ignored(Ignored, day: LocalDay?)
    }

    /// Wake events before this are night waking (e.g. Sleep Focus turned off to check the phone).
    static let earliestWake = 3 * 60
    /// Bed events from midnight until this belong to the previous day.
    static let lateBedCutoff = 6 * 60
    /// Bed events from `lateBedCutoff` until this are naps.
    static let earliestBed = 18 * 60

    private enum Placement {
        case counts(LocalDay, minutes: Int)
        case ignored(Ignored)
    }

    /// The day an event counts toward and its time in minutes since that day's midnight, or why it doesn't count.
    private static func placement(of event: Event, calendar: Calendar) -> Placement {
        let day = LocalDay(event.date, calendar: calendar)
        let minutes = ClockTime(event.date, calendar: calendar).minutesSinceMidnight
        switch event.kind {
        case .wake:
            return minutes < earliestWake ? .ignored(.night) : .counts(day, minutes: minutes)
        case .bed:
            if minutes < lateBedCutoff {
                return .counts(day.adding(days: -1), minutes: minutes + 24 * 60)
            }
            return minutes < earliestBed ? .ignored(.nap) : .counts(day, minutes: minutes)
        }
    }

    /// What to do with `event`, given the day-boundary readings already stored (any days; others are ignored).
    ///
    /// The earliest wake of the day wins, so a later one (a nap, or a second trigger) is dropped; an earlier one
    /// arriving late is still recorded, and `combine: .min` picks it. Each trigger logs one bed time a day.
    static func outcome(of event: Event, existing: [ReadingValue], calendar: Calendar = .current) -> Outcome {
        let day: LocalDay
        let minutes: Int
        switch placement(of: event, calendar: calendar) {
        case let .ignored(reason):
            return .ignored(reason, day: nil)
        case let .counts(placedDay, placedMinutes):
            (day, minutes) = (placedDay, placedMinutes)
        }
        let sameDay = existing.filter { $0.metric == event.kind.metric && $0.day == day }
        switch event.kind {
        case .wake:
            if let first = sameDay.map(\.value).min(), first <= Double(minutes) {
                return .ignored(.notFirstWake(first), day: day)
            }
        case .bed:
            if let logged = sameDay.first(where: { $0.subject == event.trigger.rawValue }) {
                return .ignored(.bedAlreadyLogged(logged.value), day: day)
            }
        }
        return .record(ReadingValue(
            source: .dayBoundary,
            metric: event.kind.metric,
            subject: event.trigger.rawValue,
            day: day,
            start: event.date,
            value: Double(minutes)
        ))
    }

    /// The days an event at `date` could count toward, for fetching the readings `outcome` compares against.
    static func candidateDays(for date: Date, calendar: Calendar = .current) -> [LocalDay] {
        let day = LocalDay(date, calendar: calendar)
        return [day.adding(days: -1), day]
    }
}

extension DayBoundary.Outcome {
    /// What the automation shows when it runs, e.g. "Wake 6:42 logged for 2026-11-07".
    var summary: String {
        func time(_ minutes: Double) -> String {
            ItemLink(metric: .wakeTime, rule: .counts(per: 1), unit: .clockTime).format(minutes)
        }
        switch self {
        case let .record(reading):
            let kind = reading.metric == .wakeTime ? "Wake" : "Bed"
            return "\(kind) \(time(reading.value)) logged for \(reading.day)"
        case .ignored(.night, _):
            return "Ignored: too early to be a wake time"
        case .ignored(.nap, _):
            return "Ignored: too early to be a bed time"
        case let .ignored(.notFirstWake(first), day):
            return "Ignored: \(day.map { "\($0)" } ?? "the day") already has a wake time of \(time(first))"
        case let .ignored(.bedAlreadyLogged(logged), day):
            return "Ignored: \(day.map { "\($0)" } ?? "the day") already has this bed time, \(time(logged))"
        }
    }
}
