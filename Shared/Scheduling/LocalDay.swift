import Foundation

/// A calendar day in local wall-clock terms, independent of time zone.
///
/// Day arithmetic is done on `ordinal` (days since 1970-01-01) using the proleptic Gregorian calendar,
/// so it never depends on time zones or DST.
struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    var ordinal: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `ordinal` (Howard Hinnant's `civil_from_days`).
    init(ordinal: Int) {
        let shifted = ordinal + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: dayOfYear - (153 * monthIndex + 2) / 5 + 1)
    }

    /// Weekday using `Calendar` numbering: 1 = Sunday … 7 = Saturday.
    var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        ((ordinal % 7 + 7) % 7 + 4) % 7 + 1
    }

    /// Months since year 0, for "every N months" arithmetic.
    var monthIndex: Int {
        year * 12 + month - 1
    }

    var daysInMonth: Int {
        Self.daysInMonth(year: year, month: month)
    }

    func adding(days: Int) -> LocalDay {
        LocalDay(ordinal: ordinal + days)
    }

    func days(until other: LocalDay) -> Int {
        other.ordinal - ordinal
    }

    /// First day of the week containing this day, where weeks start on `firstWeekday` (`Calendar` numbering).
    func startOfWeek(firstWeekday: Int) -> LocalDay {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }

    /// Compact storage form, `yyyymmdd`.
    var key: Int {
        year * 10000 + month * 100 + day
    }

    init?(key: Int) {
        let year = key / 10000
        let month = key / 100 % 100
        let day = key % 100
        guard (1 ... 12).contains(month), (1 ... Self.daysInMonth(year: year, month: month)).contains(day) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
