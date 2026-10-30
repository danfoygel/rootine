import Foundation

/// A local wall-clock time within a day. Stays at the same clock time across time zones.
struct ClockTime: Hashable, Comparable, Codable, Sendable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// When during the day an item is meant to be done. Windows never cross midnight (a day runs midnight to midnight).
enum TimeOfDay: Hashable, Codable, Sendable {
    case anytime
    case exact(ClockTime)
    case window(start: ClockTime, end: ClockTime)

    /// The time by which the item is expected to be done; `nil` for anytime items.
    var dueTime: ClockTime? {
        switch self {
        case .anytime: nil
        case let .exact(time): time
        case let .window(_, end): end
        }
    }

    /// When the v1 reminder fires: at the exact time, or when the window opens. Anytime items get none.
    var reminderTime: ClockTime? {
        switch self {
        case .anytime: nil
        case let .exact(time): time
        case let .window(start, _): start
        }
    }
}

extension TimeOfDay {
    /// Shorthand for fixtures and tests: `.at(8)`, `.at(7, 30)`.
    static func at(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
        .exact(ClockTime(hour: hour, minute: minute))
    }

    /// Shorthand for fixtures and tests: `.window(7, 9)` is 7:00–9:00.
    static func window(_ startHour: Int, _ endHour: Int) -> TimeOfDay {
        .window(start: ClockTime(hour: startHour), end: ClockTime(hour: endHour))
    }
}
