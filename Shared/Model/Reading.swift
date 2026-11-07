import Foundation
import SwiftData

/// One measurement from an outside source (Screen Time, HealthKit, a visit, an air reading) for a day.
///
/// Kept coarse, one summary per day or per stay, so CloudKit holds hundreds of records a year, not millions
/// (DATA.md, build plan). Only the iPhone writes readings; linked items turn them into automatic events.
@Model
final class Reading {
    var id = UUID()
    var sourceRaw = ""
    var metricRaw = ""
    var subject = ""
    var dayKey = 0
    var start = Date()
    var end: Date?
    var value = 0.0
    var recordedAt = Date()

    init(_ value: ReadingValue, recordedAt: Date = .now) {
        id = value.id
        sourceRaw = value.source.rawValue
        metricRaw = value.metric.rawValue
        subject = value.subject
        dayKey = value.day.key
        start = value.start
        end = value.end
        self.value = value.value
        self.recordedAt = recordedAt
    }

    var snapshot: ReadingValue? {
        LocalDay(key: dayKey).map { day in
            ReadingValue(
                id: id,
                source: ReadingSource(rawValue: sourceRaw),
                metric: ReadingMetric(rawValue: metricRaw),
                subject: subject,
                day: day,
                start: start,
                end: end,
                value: value
            )
        }
    }
}
