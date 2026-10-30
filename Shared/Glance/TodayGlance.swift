import Foundation

/// A small summary of today's list for complications and widgets.
///
/// Widget extensions run in their own process and can't see the app's SwiftData store or its relay overlay,
/// so the app writes this summary to the App Group whenever its list changes and the widget only reads it.
struct TodayGlance: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var name: String
        var symbolName: String
        var colorName: String
        /// When the item is expected to be done; `nil` for anytime items.
        var due: Date?
        var isDone: Bool
        var isCarriedOver: Bool

        /// The first moment the list would call this entry overdue (the minute after it is due).
        var overdueAt: Date? {
            due?.addingTimeInterval(60)
        }

        func isOverdue(at date: Date) -> Bool {
            guard !isDone else { return false }
            if isCarriedOver {
                return true
            }
            return overdueAt.map { $0 <= date } ?? false
        }
    }

    /// Start of the day this glance describes.
    var day: Date
    /// In urgency order, done entries last. Timed entries are already in due order, so entries that
    /// become overdue later in the day stay in the right place without re-sorting.
    var entries: [Entry]
    /// Set while the app is in test mode, so complications can say so. Optional so older saved glances decode.
    var isTestData: Bool?

    var remaining: [Entry] {
        entries.filter { !$0.isDone }
    }

    var doneCount: Int {
        entries.count { $0.isDone }
    }

    func isCurrent(at date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: day)
    }

    /// Moments after `date` when the glance would look different: entries turning overdue, and the end of the day.
    func changeDates(after date: Date, calendar: Calendar = .current) -> [Date] {
        let overdue = remaining.compactMap(\.overdueAt).filter { $0 > date }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: day).map { [$0] } ?? []
        return Set(overdue + endOfDay).sorted()
    }
}

extension TodayGlance {
    static let appGroupID = "group.com.danfoygel.rootine"
    private static let defaultsKey = "todayGlance"

    static func load() -> TodayGlance? {
        UserDefaults(suiteName: appGroupID)?
            .data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(TodayGlance.self, from: $0) }
    }

    func save() {
        UserDefaults(suiteName: Self.appGroupID)?.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
