import Foundation
import OnigiriKit

@Observable
final class CalendarModel {
    private(set) var earned: Set<Date> = []
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var targetDeficitKcal: Double?
    private(set) var totalsByDay: [Date: DayEnergyTotals] = [:]
    /// Full summary (sodium, water) for the selected day's detail card.
    private(set) var selectedDaySummary: DailyEnergySummary?
    /// A year of weigh-ins so any browsable month can show its scale change.
    private(set) var weightHistory: [WeightTrend.Point] = []

    private let health = HealthKitService()
    private var summaryGeneration = 0

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
        weightHistory = (try? await health.bodyMassHistory(days: 365)) ?? weightHistory
    }

    /// Predicted lb change for the month (its net deficit ÷ 3,500).
    func predictedLb(inMonthOf month: Date) -> Double? {
        totalDeficit(inMonthOf: month).map(WeightTrend.Change.predictedLb)
    }

    /// What the scale actually did across the month (nil when it lacks
    /// two smoothed weigh-ins).
    func actualLb(inMonthOf month: Date, now: Date = .now) -> Double? {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return WeightTrend.Change.actualLb(
            history: weightHistory, from: start, to: min(nextMonth, now)
        )
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

    /// Sodium/water for the selected day — the same numbers Today shows.
    func loadDaySummary(for day: Date) async {
        summaryGeneration += 1
        let generation = summaryGeneration
        let summary = try? await health.daySummary(for: day)
        guard generation == summaryGeneration else { return }
        selectedDaySummary = summary
    }

}
