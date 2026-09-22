import Foundation

/// "Is this data fresh enough to skip re-querying HealthKit" — the same
/// shape (a last-refreshed stamp, an age threshold, and a same-day check)
/// was hand-rolled independently in four places before this
/// (health-check audit, 2026-09-14): TodayModel, CalendarModel,
/// GoalModel, and the watch's WatchModel. A calendar DAY ROLLING OVER
/// always counts as stale regardless of the age threshold — yesterday's
/// numbers are wrong today no matter how recently they were read.
///
/// A plain value type, not `@Observable` — this is a model's own private
/// bookkeeping, never something a view binds to directly.
public struct RefreshGate: Sendable {
    public private(set) var lastRefreshed: Date?

    public init(lastRefreshed: Date? = nil) {
        self.lastRefreshed = lastRefreshed
    }

    /// Stale when nothing has ever refreshed, the calendar day rolled
    /// over since the last refresh, or the last refresh is older than
    /// `maxAge`.
    public func isStale(
        maxAge: TimeInterval, now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard let lastRefreshed else { return true }
        if !calendar.isDate(lastRefreshed, inSameDayAs: now) { return true }
        return now.timeIntervalSince(lastRefreshed) > maxAge
    }

    public mutating func markRefreshed(at date: Date = .now) {
        lastRefreshed = date
    }

    /// Forces the next `isStale` to answer true regardless of age —
    /// GoalModel's `reload()` uses this for an explicit pull that must
    /// bypass the staleness window entirely.
    public mutating func reset() {
        lastRefreshed = nil
    }
}
