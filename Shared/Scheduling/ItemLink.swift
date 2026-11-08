import Foundation

/// Where readings come from. Each source owns its readings: a source replaces its own, never another's.
/// String-backed so each data source can declare its value in its own file (DATA.md, build plan).
struct ReadingSource: RawRepresentable, Hashable, Codable, Sendable {
    var rawValue: String
}

/// What a reading measures, e.g. screen time or steps. String-backed for the same reason as `ReadingSource`.
struct ReadingMetric: RawRepresentable, Hashable, Codable, Sendable {
    var rawValue: String
}

/// A value snapshot of one reading, so evaluation stays pure and `Sendable`.
struct ReadingValue: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var source: ReadingSource
    var metric: ReadingMetric
    /// What the reading is about within the metric: an app name, a place ID. Empty when there's only one.
    var subject = ""
    /// The day the reading counts toward.
    var day: LocalDay
    var start: Date
    var end: Date?
    var value: Double
}

/// How an item is fed from readings (REQUIREMENTS.md §9, DATA.md build plan).
///
/// Stored on the item as JSON, so new sources and metrics need no schema change.
struct ItemLink: Hashable, Codable, Sendable {
    enum Rule: Hashable, Codable, Sendable {
        /// Done once the day's value reaches the threshold (e.g. at least 10,000 steps).
        case atLeast(Double)
        /// Done while the day's value stays at or under the threshold (e.g. under 1h of an app). A limit habit.
        case atMost(Double)
        /// Counted items: one unit of progress per this much of the value (e.g. 1 per 1,000 steps).
        case counts(per: Double)
    }

    /// How several readings for the same day combine into the day's value.
    enum Combine: String, Hashable, Codable, Sendable {
        case sum
        case max
        case min
        case latest
    }

    /// How values are shown in row details.
    enum Unit: Hashable, Codable, Sendable {
        case seconds
        case count
        /// Stored as 0–1, shown as a percentage.
        case fraction
        case suffix(String)
        /// Minutes since local midnight, shown as a clock time, e.g. "6:42". Past 24h is the next day's clock.
        case clockTime
    }

    var metric: ReadingMetric
    /// Only readings with this subject count; `nil` takes every subject (e.g. total screen time).
    var subject: String?
    var rule: Rule
    var combine = Combine.sum
    var unit = Unit.count

    /// Whether `reading` feeds this link.
    func matches(_ reading: ReadingValue) -> Bool {
        reading.metric == metric && (subject == nil || reading.subject == subject)
    }

    /// The day's value, or `nil` with no matching readings: no data is never the same as zero.
    func value(from readings: some Sequence<ReadingValue>) -> Double? {
        let matching = readings.filter(matches)
        guard !matching.isEmpty else { return nil }
        switch combine {
        case .sum: return matching.reduce(0) { $0 + $1.value }
        case .max: return matching.map(\.value).max()
        case .min: return matching.map(\.value).min()
        case .latest: return matching.max { $0.start < $1.start }?.value
        }
    }

    /// The progress a value implies for an item with this target.
    func progress(for value: Double, target: Int) -> Int {
        switch rule {
        case let .atLeast(threshold): value >= threshold ? target : 0
        case let .atMost(threshold): value <= threshold ? target : 0
        case let .counts(per): per > 0 ? Int((value / per).rounded(.down)) : 0
        }
    }

    var threshold: Double? {
        switch rule {
        case let .atLeast(threshold), let .atMost(threshold): threshold
        case .counts: nil
        }
    }

    /// Editor text, e.g. "screenTime · Instagram · at most 1h".
    var summary: String {
        let rule = switch rule {
        case let .atLeast(threshold): "at least \(format(threshold))"
        case let .atMost(threshold): "at most \(format(threshold))"
        case let .counts(per): "1 per \(format(per))"
        }
        return ([metric.rawValue, subject, rule] as [String?]).compactMap(\.self).joined(separator: " · ")
    }

    /// Row detail text, e.g. "52m of 1h" or "6,214".
    func label(for value: Double) -> String {
        guard let threshold else { return format(value) }
        return "\(format(value)) of \(format(threshold))"
    }

    func format(_ value: Double) -> String {
        switch unit {
        case .seconds:
            Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        case .count:
            value.formatted(.number.precision(.fractionLength(0)))
        case .fraction:
            value.formatted(.percent.precision(.fractionLength(0)))
        case let .suffix(suffix):
            "\(value.formatted(.number.precision(.fractionLength(0 ... 1)))) \(suffix)"
        case .clockTime:
            String(format: "%d:%02d", Int(value) / 60 % 24, Int(value) % 60)
        }
    }
}

/// Works out the automatic progress that readings imply for linked items.
///
/// Automatic events are kept apart from manual ones: the result is the change to the *automatic* total, so
/// applying it again does nothing, and a manual undo of an automatic completion stays undone.
enum ReadingEvaluator {
    /// Per item, the amount to record as an automatic event on `day`. Items whose day has no matching readings
    /// are left alone.
    static func changes(
        items: [ItemPlan],
        readings: [ReadingValue],
        autoTotals: [UUID: Int],
        on day: LocalDay
    ) -> [UUID: Int] {
        let todays = readings.filter { $0.day == day }
        var changes: [UUID: Int] = [:]
        for item in items {
            guard let link = item.link, let value = link.value(from: todays) else { continue }
            let change = link.progress(for: value, target: item.target) - autoTotals[item.id, default: 0]
            if change != 0 {
                changes[item.id] = change
            }
        }
        return changes
    }
}

extension TodayEntry {
    /// The day's linked value against its threshold, for the row detail. `nil` without a link or readings, and
    /// for counted links, whose progress already shows as the item's total.
    func readingLabel(from readings: some Sequence<ReadingValue>, on day: LocalDay) -> String? {
        guard let link = plan.link, link.threshold != nil,
              let value = link.value(from: readings.filter { $0.day == day }) else { return nil }
        return link.label(for: value)
    }
}
