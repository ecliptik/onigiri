import Foundation

/// Calendar-day boundaries for HealthKit queries. Uses calendar arithmetic,
/// not fixed 86 400-second days: on DST transition days the day is 23 or
/// 25 hours long, and a fixed interval either drops the last hour of logs
/// from the day's totals or double-counts the first hour of the next day.
public enum DayBounds {
    /// The day containing `date`: today ends at `now`, past days at their
    /// (DST-correct) midnight, future days collapse to an empty range.
    public static func range(
        for date: Date, now: Date, calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86400)
        return (start, min(end, max(now, start)))
    }

    /// A timestamp for logging into `day`: now when that's today, otherwise
    /// noon of that day (backfilled entries pick their meal slot explicitly,
    /// so the exact hour only affects ordering).
    public static func logTimestamp(
        for day: Date, now: Date = .now, calendar: Calendar = .current
    ) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
