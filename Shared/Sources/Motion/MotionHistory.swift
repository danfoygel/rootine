import Foundation

/// One day of the motion history screen: minutes per activity from that day's stored readings.
struct MotionHistoryDay: Identifiable, Hashable, Sendable {
    var day: LocalDay
    /// Activities with time, in display order.
    var entries: [Entry]
    /// The day has motion readings. Without any, nothing was recorded (phone off, not imported yet): no data,
    /// which isn't the same as no activity.
    var hasData: Bool
    /// The day's readings are final; otherwise its totals can still grow (today, or yesterday until 01:00).
    var isComplete: Bool

    struct Entry: Hashable, Sendable {
        var activity: MotionActivity
        var minutes: Double
    }

    var id: LocalDay {
        day
    }
}

/// The last few days of motion, built from the readings the import stores (DATA.md section 8).
enum MotionHistory {
    /// The activities listed, each counted once (walking + running would count walks twice).
    static let activities: [MotionActivity] = [.walking, .running, .cycling, .driving, .stationary]

    /// `count` days ending with `today`, newest first. Days with no motion readings are kept, with no entries.
    static func days(from readings: [ReadingValue], through today: LocalDay, count: Int = 7) -> [MotionHistoryDay] {
        let byDay = Dictionary(grouping: readings.filter { $0.source == .motion }, by: \.day)
        return (0 ..< count).map { offset in
            let day = today.adding(days: -offset)
            let readings = byDay[day] ?? []
            let entries = activities.compactMap { activity -> MotionHistoryDay.Entry? in
                let minutes = readings.filter { $0.metric == activity.metric }.reduce(0) { $0 + $1.value }
                return minutes > 0 ? MotionHistoryDay.Entry(activity: activity, minutes: minutes) : nil
            }
            let isComplete = !readings.isEmpty && readings.allSatisfy { $0.end != nil }
            return MotionHistoryDay(day: day, entries: entries, hasData: !readings.isEmpty, isComplete: isComplete)
        }
    }
}
