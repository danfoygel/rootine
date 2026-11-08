import Foundation

/// The HealthKit data Rootine reads (REQUIREMENTS.md §9, DATA.md sections 2 and 6). Pure: the iPhone's
/// `HealthReader` maps each case to its HealthKit types and turns samples into `HealthSample`s.
///
/// Each type is its own `ReadingSource`, so refreshing one type for a day replaces only that type's readings.
enum HealthType: String, CaseIterable, Codable, Sendable {
    case steps
    case distance
    case exercise
    case stand
    case water
    case mindfulness
    case daylight
    case workouts
    case sleep
    case bloodPressure
    case oxygenSaturation
    case heartRate

    /// How a day's samples become readings.
    enum Aggregation: Sendable {
        /// Total of the values (steps, ml, seconds).
        case sum
        /// Number of distinct samples (BP readings, stood hours), or per subject (workouts by activity).
        case count
        /// Time covered by the samples, overlaps counted once (sleep, mindful sessions), in seconds.
        case duration
        /// Minimum, average and time below 90% (overnight SpO2).
        case oxygen
        /// Minimum, average and maximum (heart rate).
        case range
    }

    /// Readings start at 18:00 for overnight types: the evening before belongs to the night that ends next day.
    static let nightStartHour = 18

    var source: ReadingSource {
        ReadingSource(rawValue: "health.\(rawValue)")
    }

    var aggregation: Aggregation {
        switch self {
        case .steps, .distance, .exercise, .water, .daylight: .sum
        case .stand, .workouts, .bloodPressure: .count
        case .mindfulness, .sleep: .duration
        case .oxygenSaturation: .oxygen
        case .heartRate: .range
        }
    }

    /// A night belongs to the day it ends (sleep, the O2 Ring's overnight SpO2).
    var isOvernight: Bool {
        self == .sleep || self == .oxygenSaturation
    }

    /// The metrics this type's readings carry.
    var metrics: [ReadingMetric] {
        switch self {
        case .steps: [.steps]
        case .distance: [.distance]
        case .exercise: [.exerciseTime]
        case .stand: [.standHours]
        case .water: [.water]
        case .mindfulness: [.mindfulTime]
        case .daylight: [.timeInDaylight]
        case .workouts: [.workouts]
        case .sleep: [.timeAsleep]
        case .bloodPressure: [.bloodPressureReadings]
        case .oxygenSaturation: [.oxygenMinimum, .oxygenAverage, .oxygenBelow90]
        case .heartRate: [.heartRateMinimum, .heartRateAverage, .heartRateMaximum]
        }
    }

    /// The type that produces `metric`, so the reader observes only what items link to.
    init?(metric: ReadingMetric) {
        guard let type = Self.allCases.first(where: { $0.metrics.contains(metric) }) else { return nil }
        self = type
    }

    /// The day a sample counts toward: its start's calendar day, or for overnight types the day the night ends.
    func day(of sample: HealthSample, calendar: Calendar = .current) -> LocalDay {
        let day = LocalDay(sample.start, calendar: calendar)
        guard isOvernight, calendar.component(.hour, from: sample.start) >= Self.nightStartHour else { return day }
        return day.adding(days: 1)
    }

    /// The samples to fetch for `day`: midnight to midnight, or 18:00 the evening before to 18:00 for overnight
    /// types. A sample belongs to the window its start falls in.
    func window(for day: LocalDay, calendar: Calendar = .current) -> DateInterval {
        guard isOvernight else {
            return DateInterval(start: day.startDate(calendar: calendar),
                                end: day.adding(days: 1).startDate(calendar: calendar))
        }
        let evening = ClockTime(hour: Self.nightStartHour)
        return DateInterval(start: evening.date(on: day.adding(days: -1), calendar: calendar),
                            end: evening.date(on: day, calendar: calendar))
    }
}

extension ReadingMetric {
    static let steps = ReadingMetric(rawValue: "steps")
    /// Walking and running, in km.
    static let distance = ReadingMetric(rawValue: "distance")
    /// Apple's exercise minutes, in seconds.
    static let exerciseTime = ReadingMetric(rawValue: "exerciseTime")
    /// Hours with a stand, as the Activity rings count them.
    static let standHours = ReadingMetric(rawValue: "standHours")
    /// In ml.
    static let water = ReadingMetric(rawValue: "water")
    /// In seconds.
    static let mindfulTime = ReadingMetric(rawValue: "mindfulTime")
    /// In seconds; recorded by the Watch.
    static let timeInDaylight = ReadingMetric(rawValue: "timeInDaylight")
    /// Per activity: the subject is a `HealthType.workoutActivities` name.
    static let workouts = ReadingMetric(rawValue: "workouts")
    /// Total asleep for the night, in seconds.
    static let timeAsleep = ReadingMetric(rawValue: "timeAsleep")
    static let bloodPressureReadings = ReadingMetric(rawValue: "bloodPressureReadings")
    /// Overnight SpO2 as a fraction, 0–1.
    static let oxygenMinimum = ReadingMetric(rawValue: "oxygenMinimum")
    static let oxygenAverage = ReadingMetric(rawValue: "oxygenAverage")
    /// Seconds below 90% SpO2.
    static let oxygenBelow90 = ReadingMetric(rawValue: "oxygenBelow90")
    /// In beats per minute.
    static let heartRateMinimum = ReadingMetric(rawValue: "heartRateMinimum")
    static let heartRateAverage = ReadingMetric(rawValue: "heartRateAverage")
    static let heartRateMaximum = ReadingMetric(rawValue: "heartRateMaximum")
}

extension HealthType {
    /// Workout activities with their own subject; every other activity counts as "Other".
    static let workoutActivities = ["Running", "Walking", "Cycling", "Swimming", "Hiking", "Strength", "Yoga",
                                    "HIIT", "Other"]
}
