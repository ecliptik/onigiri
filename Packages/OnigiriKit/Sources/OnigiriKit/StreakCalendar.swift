import Foundation

/// One calendar day's energy totals from HealthKit.
public struct DayEnergyTotals: Sendable, Equatable {
    public let day: Date
    public let intakeKcal: Double
    public let burnKcal: Double

    public init(day: Date, intakeKcal: Double, burnKcal: Double) {
        self.day = day
        self.intakeKcal = intakeKcal
        self.burnKcal = burnKcal
    }

    public var deficitKcal: Double { burnKcal - intakeKcal }
}

/// The gamification rules: which days earned an onigiri, and the streak.
public enum StreakCalendar {
    /// A day counts as tracked when enough food was logged to trust its
    /// numbers. Below the threshold it's a missed day: streak-breaking,
    /// and excluded from the month's totals (sparse early-adoption days
    /// were skewing them). 0 disables the threshold — any logging counts.
    public static func isTracked(_ day: DayEnergyTotals, untrackedBelowKcal: Double) -> Bool {
        day.intakeKcal > 0 && day.intakeKcal >= untrackedBelowKcal
    }

    /// A day earns an onigiri when it was tracked and the deficit met the
    /// target — or showed any deficit at all when no goal is set. The
    /// badge is awarded only once the day COMPLETES: a live "earned" at
    /// breakfast (trivially at deficit) read as a broken meter.
    public static func earnedDays(
        totals: [DayEnergyTotals],
        targetDeficitKcal: Double?,
        untrackedBelowKcal: Double = 0,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(totals.compactMap { day in
            guard !calendar.isDate(day.day, inSameDayAs: today),
                  day.day < today,
                  isTracked(day, untrackedBelowKcal: untrackedBelowKcal) else { return nil }
            let met: Bool
            if let target = targetDeficitKcal, target > 0 {
                met = day.deficitKcal >= target
            } else {
                met = day.deficitKcal > 0
            }
            return met ? calendar.startOfDay(for: day.day) : nil
        })
    }

    /// Consecutive earned days counting back from today — or from yesterday,
    /// so a still-in-progress today doesn't break the streak.
    public static func currentStreak(
        earned: Set<Date>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        var day = calendar.startOfDay(for: today)
        if !earned.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while earned.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Earned count within the month containing `month`.
    public static func earnedCount(
        inMonthOf month: Date,
        earned: Set<Date>,
        calendar: Calendar = .current
    ) -> Int {
        earned.count { calendar.isDate($0, equalTo: month, toGranularity: .month) }
    }

    /// The longest consecutive run of earned days, ever — drives the
    /// milestone badges.
    public static func bestStreak(
        earned: Set<Date>,
        calendar: Calendar = .current
    ) -> Int {
        var best = 0
        for day in earned {
            // Only count runs from their first day.
            if let previous = calendar.date(byAdding: .day, value: -1, to: day),
               earned.contains(previous) {
                continue
            }
            var length = 0
            var current = day
            while earned.contains(current) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            best = max(best, length)
        }
        return best
    }
}
