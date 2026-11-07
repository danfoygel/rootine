import Foundation

/// One HealthKit sample as plain values, so aggregation stays pure and testable without HealthKit.
struct HealthSample: Hashable, Sendable {
    var start: Date
    var end: Date
    /// In the type's reading unit (steps, km, ml, seconds, a 0–1 fraction, bpm). Unused for counts and durations.
    var value = 0.0
    /// A workout's activity; empty otherwise.
    var subject = ""
}

/// Turns one day's samples of a type into that day's readings: one summary per metric, never raw samples
/// (DATA.md, build plan).
enum HealthAggregator {
    /// SpO2 below this counts toward `oxygenBelow90`.
    static let lowOxygen = 0.9
    /// A point sample (start == end) lasts until the next one, but no longer than this.
    static let maxSampleGap: TimeInterval = 300

    /// `type`'s readings for `day`, from `samples`. Samples that count toward another day are ignored, and
    /// exact duplicates (ViHealth re-syncing a night with the same values and times) count once. A day with no
    /// samples has no readings: no data is never the same as zero.
    static func readings(
        _ type: HealthType,
        from samples: [HealthSample],
        on day: LocalDay,
        calendar: Calendar = .current
    ) -> [ReadingValue] {
        let samples = Array(Set(samples.filter { type.day(of: $0, calendar: calendar) == day }))
            .sorted { ($0.start, $0.end, $0.value, $0.subject) < ($1.start, $1.end, $1.value, $1.subject) }
        guard let first = samples.first else { return [] }
        let start = first.start
        let end = samples.map(\.end).max() ?? start
        func reading(_ metric: ReadingMetric, _ value: Double, subject: String = "") -> ReadingValue {
            ReadingValue(source: type.source, metric: metric, subject: subject, day: day, start: start, end: end,
                         value: value)
        }
        let metric = type.metrics[0]
        switch type.aggregation {
        case .sum:
            return [reading(metric, samples.reduce(0) { $0 + $1.value })]
        case .count:
            let bySubject = Dictionary(grouping: samples, by: \.subject)
            return bySubject.keys.sorted().map { reading(metric, Double(bySubject[$0]?.count ?? 0), subject: $0) }
        case .duration:
            return [reading(metric, coveredTime(samples))]
        case .oxygen:
            let values = samples.map(\.value)
            let below = zip(samples, durations(samples)).filter { $0.0.value < lowOxygen }.reduce(0) { $0 + $1.1 }
            return [
                reading(.oxygenMinimum, values.min() ?? 0),
                reading(.oxygenAverage, average(values)),
                reading(.oxygenBelow90, below),
            ]
        case .range:
            let values = samples.map(\.value)
            return [
                reading(.heartRateMinimum, values.min() ?? 0),
                reading(.heartRateAverage, average(values)),
                reading(.heartRateMaximum, values.max() ?? 0),
            ]
        }
    }

    /// The days whose readings `samples` change, limited to the last `lookback` days so a first run or a late
    /// re-sync of old history doesn't write a reading per day for years. Today is always included, which also
    /// picks up today's deletions (HealthKit's deleted objects carry no date).
    static func affectedDays(
        _ type: HealthType,
        by samples: [HealthSample],
        today: LocalDay,
        lookback: Int,
        calendar: Calendar = .current
    ) -> [LocalDay] {
        let earliest = today.adding(days: -lookback)
        let days = Set(samples.map { type.day(of: $0, calendar: calendar) }).union([today])
        return days.filter { $0 >= earliest && $0 <= today }.sorted()
    }

    /// Whether `new` says the same as `existing`, so an unchanged day isn't rewritten (and re-synced).
    static func isUnchanged(_ existing: [ReadingValue], _ new: [ReadingValue]) -> Bool {
        func key(_ readings: [ReadingValue]) -> [String: Double] {
            Dictionary(readings.map { ("\($0.metric.rawValue)|\($0.subject)", $0.value) }) { first, _ in first }
        }
        return existing.count == new.count && key(existing) == key(new)
    }

    /// Time covered by at least one sample, so overlapping sources (Watch and a sleep app) count once.
    private static func coveredTime(_ samples: [HealthSample]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: DateInterval?
        for sample in samples where sample.end > sample.start {
            if let open = current, sample.start <= open.end {
                current = DateInterval(start: open.start, end: max(open.end, sample.end))
            } else {
                total += current?.duration ?? 0
                current = DateInterval(start: sample.start, end: sample.end)
            }
        }
        return total + (current?.duration ?? 0)
    }

    /// How long each sample (sorted by start) lasted: its own span, or for a point sample the gap to the next
    /// one, capped at `maxSampleGap`. A final point sample counts for nothing.
    private static func durations(_ samples: [HealthSample]) -> [TimeInterval] {
        samples.indices.map { index in
            let sample = samples[index]
            if sample.end > sample.start {
                return sample.end.timeIntervalSince(sample.start)
            }
            let next = samples[(index + 1)...].first { $0.start > sample.start }
            return next.map { min($0.start.timeIntervalSince(sample.start), maxSampleGap) } ?? 0
        }
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
