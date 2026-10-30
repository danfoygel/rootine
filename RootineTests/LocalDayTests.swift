import Foundation
import Testing

struct LocalDayTests {
    @Test(arguments: [
        LocalDay(year: 1970, month: 1, day: 1),
        LocalDay(year: 2000, month: 2, day: 29),
        LocalDay(year: 2026, month: 10, day: 30),
        LocalDay(year: 1969, month: 12, day: 31),
        LocalDay(year: 2100, month: 3, day: 1),
    ])
    func ordinalRoundTrips(day: LocalDay) {
        #expect(LocalDay(ordinal: day.ordinal) == day)
        #expect(LocalDay(key: day.key) == day)
    }

    @Test func knownOrdinalsAndWeekdays() {
        #expect(LocalDay(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(LocalDay(year: 1970, month: 1, day: 1).weekday == 5) // Thursday
        #expect(LocalDay(year: 2026, month: 10, day: 30).weekday == 6) // Friday
        #expect(LocalDay(year: 1969, month: 12, day: 28).weekday == 1) // Sunday
    }

    @Test func dayArithmeticCrossesMonthsAndLeapDays() {
        #expect(LocalDay(year: 2024, month: 2, day: 28).adding(days: 1) == LocalDay(year: 2024, month: 2, day: 29))
        #expect(LocalDay(year: 2025, month: 2, day: 28).adding(days: 1) == LocalDay(year: 2025, month: 3, day: 1))
        #expect(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDay(year: 2027, month: 1, day: 1))
        #expect(LocalDay(year: 2026, month: 1, day: 1).days(until: LocalDay(year: 2027, month: 1, day: 1)) == 365)
    }

    @Test func startOfWeekHonoursFirstWeekday() {
        let friday = LocalDay(year: 2026, month: 10, day: 30)
        #expect(friday.startOfWeek(firstWeekday: 2) == LocalDay(year: 2026, month: 10, day: 26)) // Monday
        #expect(friday.startOfWeek(firstWeekday: 1) == LocalDay(year: 2026, month: 10, day: 25)) // Sunday
        let monday = LocalDay(year: 2026, month: 10, day: 26)
        #expect(monday.startOfWeek(firstWeekday: 2) == monday)
    }

    @Test func invalidKeysAreRejected() {
        #expect(LocalDay(key: 20_250_229) == nil)
        #expect(LocalDay(key: 20_261_301) == nil)
        #expect(LocalDay(key: 0) == nil)
    }

    @Test func convertsFromDateInGivenTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // 2026-10-31 03:00 UTC is still the 30th in Los Angeles.
        let date = Date(timeIntervalSince1970: 1_793_415_600)
        #expect(LocalDay(date, calendar: calendar) == LocalDay(year: 2026, month: 10, day: 30))
    }
}
