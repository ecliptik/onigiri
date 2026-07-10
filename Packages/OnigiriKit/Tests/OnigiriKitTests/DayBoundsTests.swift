import Testing
import Foundation
@testable import OnigiriKit

struct DayBoundsTests {
    /// A US calendar where 2026-03-08 springs forward and 2026-11-01 falls
    /// back — day lengths of 23 and 25 hours.
    private var pacific: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func fallBackDayIs25HoursLong() {
        let calendar = pacific
        let now = date(2026, 11, 5, 12, calendar: calendar)
        let day = date(2026, 11, 1, 10, calendar: calendar)
        let (start, end) = DayBounds.range(for: day, now: now, calendar: calendar)
        // 23:30 on the fall-back day must still be inside the day.
        let lateEvening = date(2026, 11, 1, 23, calendar: calendar).addingTimeInterval(1800)
        #expect(lateEvening >= start && lateEvening < end)
        #expect(end.timeIntervalSince(start) == 25 * 3600)
    }

    @Test func springForwardDayIs23HoursLong() {
        let calendar = pacific
        let now = date(2026, 3, 10, 12, calendar: calendar)
        let day = date(2026, 3, 8, 10, calendar: calendar)
        let (start, end) = DayBounds.range(for: day, now: now, calendar: calendar)
        #expect(end.timeIntervalSince(start) == 23 * 3600)
        // Midnight of March 9 belongs to March 9, not to the 8th.
        let nextMidnight = date(2026, 3, 9, 0, calendar: calendar)
        #expect(end == nextMidnight)
    }

    @Test func todayClampsToNowAndFutureDaysAreEmpty() {
        let calendar = pacific
        let now = date(2026, 7, 10, 15, calendar: calendar)
        let today = DayBounds.range(for: now, now: now, calendar: calendar)
        #expect(today.end == now)
        let tomorrow = date(2026, 7, 11, 9, calendar: calendar)
        let future = DayBounds.range(for: tomorrow, now: now, calendar: calendar)
        #expect(future.start == future.end)
    }

    @Test func backfillTimestampIsNoonForPastDaysAndNowForToday() {
        let calendar = pacific
        let now = date(2026, 7, 10, 15, calendar: calendar)
        #expect(DayBounds.logTimestamp(for: now, now: now, calendar: calendar) == now)
        let pastDay = date(2026, 7, 8, 9, calendar: calendar)
        let stamp = DayBounds.logTimestamp(for: pastDay, now: now, calendar: calendar)
        #expect(calendar.component(.hour, from: stamp) == 12)
        #expect(calendar.isDate(stamp, inSameDayAs: pastDay))
    }
}
