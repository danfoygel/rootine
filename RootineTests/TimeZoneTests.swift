import Foundation
import Testing

private func calendar(_ identifier: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: identifier))
    return calendar
}

private func date(_ iso: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: iso))
}

struct TimeZoneTests {
    @Test(arguments: ["America/New_York", "Europe/London", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago"])
    func midnightBoundaries(zone: String) throws {
        let calendar = try calendar(zone)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        #expect(LocalDay(start, calendar: calendar) == day(10, 30))
        #expect(LocalDay(start.addingTimeInterval(-1), calendar: calendar) == day(10, 29))
        #expect(LocalDay(start.addingTimeInterval(24 * 3600 - 1), calendar: calendar) == day(10, 30))
        #expect(ClockTime(start, calendar: calendar) == ClockTime(hour: 0))
        #expect(ClockTime(start.addingTimeInterval(-1), calendar: calendar) == ClockTime(hour: 23, minute: 59))
    }

    @Test func farApartZonesSeeDifferentDaysForOneInstant() throws {
        let instant = try date("2026-10-30T11:00:00Z")
        #expect(try LocalDay(instant, calendar: calendar("Pacific/Kiritimati")) == day(10, 31)) // UTC+14
        #expect(try LocalDay(instant, calendar: calendar("Pacific/Pago_Pago")) == day(10, 30)) // UTC−11
    }

    @Test(arguments: [
        ("America/New_York", "2026-03-08T06:59:00Z", "2026-03-08T07:00:00Z", 8), // spring forward
        ("America/New_York", "2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", 1), // fall back: 1:30 twice
        ("Europe/London", "2026-03-29T00:59:00Z", "2026-03-29T01:00:00Z", 29),
        ("Europe/London", "2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z", 25),
    ])
    func dstTransitionsStayOnTheSameDay(zone: String, before: String, after: String, dayOfMonth: Int) throws {
        let calendar = try calendar(zone)
        let first = try LocalDay(date(before), calendar: calendar)
        let second = try LocalDay(date(after), calendar: calendar)
        #expect(first == second)
        #expect(first.day == dayOfMonth)
    }

    @Test func fallBackRepeatsTheSameWallClockTime() throws {
        let calendar = try calendar("America/New_York")
        let daylight = try ClockTime(date("2026-11-01T05:30:00Z"), calendar: calendar)
        let standard = try ClockTime(date("2026-11-01T06:30:00Z"), calendar: calendar)
        #expect(daylight == ClockTime(hour: 1, minute: 30))
        #expect(standard == daylight)
    }

    /// REQUIREMENTS §14: times are local wall-clock times, so 8:00 stays 8:00 in any zone.
    @Test(arguments: ["America/Los_Angeles", "Europe/London", "Asia/Tokyo", "Australia/Lord_Howe"])
    func wallClockTimesRoundTripInEveryZone(zone: String) throws {
        let calendar = try calendar(zone)
        for time in [ClockTime(hour: 8), ClockTime(hour: 0), ClockTime(hour: 23, minute: 59)] {
            let date = time.date(on: day(10, 30), calendar: calendar)
            #expect(ClockTime(date, calendar: calendar) == time)
            #expect(LocalDay(date, calendar: calendar) == day(10, 30))
        }
    }

    /// 2:30 doesn't exist on the spring-forward day; the reminder date lands later that same day.
    @Test func missingWallClockTimeResolvesWithinTheSameDay() throws {
        let calendar = try calendar("America/New_York")
        let date = ClockTime(hour: 2, minute: 30).date(on: day(3, 8), calendar: calendar)
        #expect(LocalDay(date, calendar: calendar) == day(3, 8))
        #expect(ClockTime(date, calendar: calendar) > ClockTime(hour: 2, minute: 30))
    }
}
