import Foundation

extension ReadingSource {
    /// CoreMotion activity on the iPhone (DATA.md section 8).
    static let motion = ReadingSource(rawValue: "motion")
}

extension ReadingMetric {
    static let walkingMinutes = ReadingMetric(rawValue: "walkingMinutes")
    static let runningMinutes = ReadingMetric(rawValue: "runningMinutes")
    static let cyclingMinutes = ReadingMetric(rawValue: "cyclingMinutes")
    static let automotiveMinutes = ReadingMetric(rawValue: "automotiveMinutes")
    static let stationaryMinutes = ReadingMetric(rawValue: "stationaryMinutes")
    /// Walking plus running, so "Walk ≥ 20 min" is one link: an item has only one.
    static let onFootMinutes = ReadingMetric(rawValue: "onFootMinutes")
}

/// One activity change from `CMMotionActivityManager`, as a `Sendable` value. Several flags can be set at once
/// (driving and stationary at a red light), or none.
struct MotionEvent: Hashable, Sendable {
    enum Confidence: Int, Hashable, Sendable {
        case low
        case medium
        case high
    }

    var start: Date
    var stationary = false
    var walking = false
    var running = false
    var automotive = false
    var cycling = false
    var unknown = false
    var confidence = Confidence.high
}

/// The single label a stretch of time gets, in priority order.
enum MotionKind: String, CaseIterable, Hashable, Codable, Sendable {
    case automotive
    case cycling
    case running
    case walking
    case stationary
    case unknown

    /// The reading metric for this kind's daily minutes; unknown time isn't stored.
    var metric: ReadingMetric? {
        switch self {
        case .automotive: .automotiveMinutes
        case .cycling: .cyclingMinutes
        case .running: .runningMinutes
        case .walking: .walkingMinutes
        case .stationary: .stationaryMinutes
        case .unknown: nil
        }
    }
}

/// A stretch of time with one label.
struct MotionSegment: Hashable, Codable, Sendable {
    var kind: MotionKind
    var start: Date
    var end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// One local day's activity: minutes per kind, and the merged segments behind them.
struct MotionDaySummary: Hashable, Sendable {
    var day: LocalDay
    var dayStart: Date
    var dayEnd: Date
    /// Minutes per kind, every kind present (zero when none).
    var minutes: [MotionKind: Double]
    var segments: [MotionSegment]
    /// The day ended more than the import lag ago, so its totals won't change.
    var isComplete: Bool

    /// The day as readings: one per kind, plus walking + running as on-foot minutes.
    ///
    /// Until the day is complete, kinds with no time are left out rather than stored as zero. A limit such as
    /// "no driving on Sunday" (`atMost(0)`) then waits for the finished day instead of reading as done at
    /// breakfast. Complete days carry readings for every kind, zeros included, and an `end` at midnight. A day
    /// with no activity recorded at all (phone off, Fitness Tracking off) has no readings: no data isn't zero.
    func readings() -> [ReadingValue] {
        guard !segments.isEmpty else { return [] }
        var values = MotionKind.allCases.compactMap { kind in kind.metric.map { ($0, minutes[kind] ?? 0) } }
        values.append((.onFootMinutes, (minutes[.walking] ?? 0) + (minutes[.running] ?? 0)))
        return values.compactMap { metric, value in
            guard isComplete || value > 0 else { return nil }
            return ReadingValue(source: .motion, metric: metric, day: day, start: dayStart,
                                end: isComplete ? dayEnd : nil, value: value)
        }
    }
}

/// Turns CoreMotion activity changes into daily minutes per kind (DATA.md section 8). Pure, so every rule is
/// unit tested without hardware.
struct MotionSummariser: Sendable {
    /// A segment lasts until the next event, but no longer than this: a longer silence is missing data.
    var maxGap: TimeInterval = 3 * 3600
    /// A run of segments this short between two of the same kind is absorbed into them.
    var blip: TimeInterval = 2 * 60
    /// Shorter segments of a kind are dropped as noise.
    var minimum: [MotionKind: TimeInterval] = [
        .walking: 60, .running: 60, .cycling: 3 * 60, .automotive: 3 * 60,
    ]
    /// A day is complete once it ended this long before the import; CoreMotion results can lag by minutes.
    var completionLag: TimeInterval = 3600
    var calendar = Calendar.current

    /// Step 1 and 2: one label per event, by priority; low confidence counts as unknown.
    static func kind(of event: MotionEvent) -> MotionKind {
        guard event.confidence != .low else { return .unknown }
        if event.automotive {
            return .automotive
        }
        if event.cycling {
            return .cycling
        }
        if event.running {
            return .running
        }
        if event.walking {
            return .walking
        }
        if event.stationary {
            return .stationary
        }
        return .unknown
    }

    /// Daily summaries for every day that starts at or after `from` and has begun by `now`. Days before `from`
    /// are left out because the query didn't cover them from midnight.
    func summarise(_ events: [MotionEvent], from: Date, now: Date) -> [MotionDaySummary] {
        let pieces = segments(events, now: now).flatMap(splitAtMidnight)
            .compactMap { clip($0, from: from, to: now) }
        var days: [MotionDaySummary] = []
        var dayStart = calendar.startOfDay(for: from)
        if dayStart < from, let next = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            dayStart = next
        }
        while dayStart < now, let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            let segments = pieces.filter { $0.start >= dayStart && $0.end <= dayEnd }
            var minutes = Dictionary(uniqueKeysWithValues: MotionKind.allCases.map { ($0, 0.0) })
            for segment in segments {
                minutes[segment.kind, default: 0] += segment.duration / 60
            }
            days.append(MotionDaySummary(
                day: LocalDay(dayStart, calendar: calendar),
                dayStart: dayStart,
                dayEnd: dayEnd,
                minutes: minutes,
                segments: segments,
                isComplete: dayEnd.addingTimeInterval(completionLag) <= now
            ))
            dayStart = dayEnd
        }
        return days
    }

    /// Steps 1–5: labelled, gap-capped, merged segments with noise dropped, not yet split at midnight. Merging
    /// before the split keeps a drive across midnight from being dropped as two short pieces.
    func segments(_ events: [MotionEvent], now: Date) -> [MotionSegment] {
        let sorted = events.sorted { $0.start < $1.start }
        var raw: [MotionSegment] = []
        for (index, event) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].start : now
            let end = min(next, event.start.addingTimeInterval(maxGap))
            if end > event.start {
                raw.append(MotionSegment(kind: Self.kind(of: event), start: event.start, end: end))
            }
        }
        return merge(raw).filter { $0.duration >= minimum[$0.kind, default: 0] }
    }

    /// Step 4: joins touching segments of the same kind, and absorbs a short run between two of the same kind.
    func merge(_ segments: [MotionSegment]) -> [MotionSegment] {
        var merged: [MotionSegment] = []
        var index = 0
        while index < segments.count {
            var current = segments[index]
            index += 1
            while index < segments.count {
                let next = segments[index]
                if next.start == current.end, next.kind == current.kind {
                    current.end = next.end
                    index += 1
                } else if let resume = blipEnd(after: current, in: segments, from: index) {
                    current.end = segments[resume].end
                    index = resume + 1
                } else {
                    break
                }
            }
            merged.append(current)
        }
        return merged
    }

    /// The index of the segment of `current`'s kind that resumes after a touching run of other kinds lasting
    /// under `blip`, or `nil`.
    private func blipEnd(after current: MotionSegment, in segments: [MotionSegment], from start: Int) -> Int? {
        var end = current.end
        var index = start
        while index < segments.count, segments[index].start == end {
            let segment = segments[index]
            if segment.kind == current.kind {
                return index > start ? index : nil
            }
            guard segment.end.timeIntervalSince(current.end) < blip else { return nil }
            end = segment.end
            index += 1
        }
        return nil
    }

    private func splitAtMidnight(_ segment: MotionSegment) -> [MotionSegment] {
        var pieces: [MotionSegment] = []
        var piece = segment
        while let midnight = nextMidnight(after: piece.start), midnight < piece.end {
            pieces.append(MotionSegment(kind: piece.kind, start: piece.start, end: midnight))
            piece.start = midnight
        }
        pieces.append(piece)
        return pieces
    }

    private func nextMidnight(after date: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    private func clip(_ segment: MotionSegment, from: Date, to now: Date) -> MotionSegment? {
        let clipped = MotionSegment(kind: segment.kind, start: max(segment.start, from), end: min(segment.end, now))
        return clipped.end > clipped.start ? clipped : nil
    }
}

/// Where each import starts and resumes. CoreMotion keeps 7 days, and each run recomputes whole days.
enum MotionImportWindow {
    static let history: TimeInterval = 7 * 24 * 3600
    /// The query starts this long before the first day, to pick up the activity already under way at midnight.
    static let lead: TimeInterval = 3600

    /// The first midnight to summarise: the day to resume from, or the oldest whole day CoreMotion still has
    /// (with room for the lead).
    static func firstDay(resumingFrom resume: Date?, now: Date, calendar: Calendar = .current) -> Date {
        let earliest = now.addingTimeInterval(-history + lead)
        var oldest = calendar.startOfDay(for: earliest)
        if oldest < earliest, let next = calendar.date(byAdding: .day, value: 1, to: oldest) {
            oldest = next
        }
        guard let resume else { return oldest }
        return max(calendar.startOfDay(for: resume), oldest)
    }

    /// Where the next import resumes: the first day not yet complete, so it's recomputed until it is.
    static func resume(after summaries: [MotionDaySummary]) -> Date? {
        summaries.first { !$0.isComplete }?.dayStart
    }
}
