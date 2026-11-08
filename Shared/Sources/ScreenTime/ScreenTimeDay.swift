import Foundation

/// One day of stored Screen Time as Settings → Screen Time shows it, so the two can be compared side by side.
struct ScreenTimeDay: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        var name: String
        var seconds: Double

        var id: String {
            name
        }
    }

    /// Most used first; names that tie are alphabetical.
    var apps: [Entry]
    var websites: [Entry]

    /// The day's Screen Time readings, apps and websites apart.
    init(readings: some Sequence<ReadingValue>, on day: LocalDay) {
        let days = readings.filter { $0.source == .screenTime && $0.day == day }
        func entries(_ metric: ReadingMetric) -> [Entry] {
            var seconds: [String: Double] = [:]
            for reading in days where reading.metric == metric {
                seconds[reading.subject, default: 0] += reading.value
            }
            let entries = seconds.map { Entry(name: $0.key, seconds: $0.value) }
            return entries.sorted { lhs, rhs in
                lhs.seconds != rhs.seconds ? lhs.seconds > rhs.seconds : lhs.name < rhs.name
            }
        }
        apps = entries(.screenTime)
        websites = entries(.websiteTime)
    }

    var isEmpty: Bool {
        apps.isEmpty && websites.isEmpty
    }

    /// The day's total across apps, like the big number in Settings → Screen Time. Websites are left out,
    /// since Safari's time already includes them.
    var total: Double {
        apps.reduce(0) { $0 + $1.seconds }
    }

    /// Exact to the second, in Screen Time's style: "1h 6m 40s", "52m", "59s". Exact, so the comparison with
    /// Settings holds whichever way it rounds.
    static func format(_ seconds: Double) -> String {
        let seconds = max(0, Int(seconds))
        let parts = [(seconds / 3600, "h"), (seconds % 3600 / 60, "m"), (seconds % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
}
