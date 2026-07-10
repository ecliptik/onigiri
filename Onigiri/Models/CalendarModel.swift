import Foundation
import OnigiriKit

@Observable
final class CalendarModel {
    private(set) var earned: Set<Date> = []
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var targetDeficitKcal: Double?
    private(set) var totalsByDay: [Date: DayEnergyTotals] = [:]

    private let health = HealthKitService()

    func refresh(goal: SyncedGoal?) async {
        // Today's plan supplies the deficit target the calendar judges against.
        let plan = await DailyPlanLoader.load(goal: goal)
        targetDeficitKcal = plan.deficitTargetKcal
        let totals = (try? await health.dailyEnergyTotals()) ?? []
        let calendar = Calendar.current
        totalsByDay = Dictionary(uniqueKeysWithValues: totals.map {
            (calendar.startOfDay(for: $0.day), $0)
        })
        earned = StreakCalendar.earnedDays(totals: totals, targetDeficitKcal: plan.deficitTargetKcal)
        streak = StreakCalendar.currentStreak(earned: earned)
        bestStreak = StreakCalendar.bestStreak(earned: earned)
    }

    /// Net deficit summed across the month's recorded days (nil when none) —
    /// the month's total "burned off" calories. Surplus days subtract.
    func totalDeficit(inMonthOf month: Date) -> Double? {
        let calendar = Calendar.current
        let deficits = totalsByDay
            .filter { calendar.isDate($0.key, equalTo: month, toGranularity: .month) }
            .map(\.value.deficitKcal)
        guard !deficits.isEmpty else { return nil }
        return deficits.reduce(0, +)
    }

    func earnedCount(inMonthOf month: Date) -> Int {
        StreakCalendar.earnedCount(inMonthOf: month, earned: earned)
    }

}
