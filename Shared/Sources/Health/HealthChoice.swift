import Foundation

/// A Health metric an item can link to, with the unit the editor asks for (REQUIREMENTS.md §9: the user picks
/// the type and a threshold; there are no presets).
struct HealthChoice: Identifiable, Hashable, Sendable {
    enum Rule: String, CaseIterable, Identifiable, Sendable {
        case atLeast
        case atMost
        /// Counted items: one unit of progress per amount.
        case counts

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .atLeast: "At Least"
            case .atMost: "At Most"
            case .counts: "1 Per"
            }
        }
    }

    var metric: ReadingMetric
    var title: String
    /// The unit amounts are typed in, e.g. "min".
    var entryUnit: String
    /// Reading units per entry unit: 60 for minutes read as seconds, 0.01 for a percentage read as 0–1.
    var scale = 1.0
    var unit: ItemLink.Unit
    var defaultAmount: Double
    /// A limit, like time below 90% SpO2, rather than a goal.
    var isLimit = false

    var id: String {
        metric.rawValue
    }

    var type: HealthType? {
        HealthType(metric: metric)
    }

    /// The default rule for a new link on an item of `kind`.
    func defaultRule(for kind: ItemKind) -> Rule {
        kind == .counted ? .counts : isLimit ? .atMost : .atLeast
    }

    /// A link for `amount` in entry units. `subject` narrows workouts to one activity.
    func link(_ rule: Rule, amount: Double, subject: String? = nil) -> ItemLink {
        let value = amount * scale
        let linkRule: ItemLink.Rule = switch rule {
        case .atLeast: .atLeast(value)
        case .atMost: .atMost(value)
        case .counts: .counts(per: value)
        }
        return ItemLink(metric: metric, subject: subject, rule: linkRule, unit: unit)
    }

    /// The rule and amount in entry units of an existing link to this metric.
    func entry(for link: ItemLink) -> (rule: Rule, amount: Double) {
        let (rule, value): (Rule, Double) = switch link.rule {
        case let .atLeast(value): (.atLeast, value)
        case let .atMost(value): (.atMost, value)
        case let .counts(per): (.counts, per)
        }
        return (rule, scale > 0 ? value / scale : value)
    }

    static func choice(for metric: ReadingMetric) -> HealthChoice? {
        all.first { $0.metric == metric }
    }

    static let all: [HealthChoice] = [
        HealthChoice(metric: .steps, title: "Steps", entryUnit: "steps", unit: .count, defaultAmount: 10000),
        HealthChoice(metric: .distance, title: "Walking + Running Distance", entryUnit: "km", unit: .suffix("km"),
                     defaultAmount: 5),
        HealthChoice(metric: .exerciseTime, title: "Exercise Minutes", entryUnit: "min", scale: 60,
                     unit: .seconds, defaultAmount: 30),
        HealthChoice(metric: .standHours, title: "Stand Hours", entryUnit: "hours", unit: .count, defaultAmount: 12),
        HealthChoice(metric: .workouts, title: "Workouts", entryUnit: "workouts", unit: .count, defaultAmount: 1),
        HealthChoice(metric: .water, title: "Water", entryUnit: "ml", unit: .suffix("ml"), defaultAmount: 2000),
        HealthChoice(metric: .timeAsleep, title: "Time Asleep", entryUnit: "hours", scale: 3600, unit: .seconds,
                     defaultAmount: 7),
        HealthChoice(metric: .mindfulTime, title: "Mindful Minutes", entryUnit: "min", scale: 60, unit: .seconds,
                     defaultAmount: 10),
        HealthChoice(metric: .timeInDaylight, title: "Time in Daylight", entryUnit: "min", scale: 60,
                     unit: .seconds, defaultAmount: 20),
        HealthChoice(metric: .bloodPressureReadings, title: "Blood Pressure Readings", entryUnit: "readings",
                     unit: .count, defaultAmount: 1),
        HealthChoice(metric: .oxygenMinimum, title: "Overnight SpO2, Lowest", entryUnit: "%", scale: 0.01,
                     unit: .fraction, defaultAmount: 90),
        HealthChoice(metric: .oxygenAverage, title: "Overnight SpO2, Average", entryUnit: "%", scale: 0.01,
                     unit: .fraction, defaultAmount: 95),
        HealthChoice(metric: .oxygenBelow90, title: "Overnight Time Below 90% SpO2", entryUnit: "min", scale: 60,
                     unit: .seconds, defaultAmount: 5, isLimit: true),
        HealthChoice(metric: .heartRateMinimum, title: "Heart Rate, Lowest", entryUnit: "bpm", unit: .suffix("bpm"),
                     defaultAmount: 60),
        HealthChoice(metric: .heartRateAverage, title: "Heart Rate, Average", entryUnit: "bpm", unit: .suffix("bpm"),
                     defaultAmount: 80),
        HealthChoice(metric: .heartRateMaximum, title: "Heart Rate, Highest", entryUnit: "bpm", unit: .suffix("bpm"),
                     defaultAmount: 150, isLimit: true),
    ]
}
