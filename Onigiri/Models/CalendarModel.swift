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
    /// Month-detail extras, loaded on push (nil while loading).
    private(set) var monthWaterOz: Double?
    private(set) var monthFoodEntries: Int?

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
        // Badges are awarded when a day completes, and days under the
        // untracked threshold never qualify.
        earned = StreakCalendar.earnedDays(
            totals: totals,
            targetDeficitKcal: plan.deficitTargetKcal,
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        streak = StreakCalendar.currentStreak(earned: earned)
        bestStreak = StreakCalendar.bestStreak(earned: earned)
        weightHistory = (try? await health.bodyMassHistory(days: 365)) ?? weightHistory
    }

    /// Water total and eating-event count for the month detail.
    func loadMonthStats(for month: Date) async {
        monthWaterOz = nil
        monthFoodEntries = nil
        let stats = try? await health.monthStats(for: month)
        monthWaterOz = stats?.waterOz
        monthFoodEntries = stats?.foodEntryCount
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

    /// The month's days that clear the untracked threshold — the set the
    /// month stats are computed over.
    private func trackedDays(inMonthOf month: Date) -> [DayEnergyTotals] {
        let calendar = Calendar.current
        return totalsByDay
            .filter { calendar.isDate($0.key, equalTo: month, toGranularity: .month) }
            .map(\.value)
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: SharedStore.untrackedBelowKcal) }
    }

    /// Net deficit summed across the month's TRACKED days (nil when none) —
    /// untracked days would skew it with phantom full-burn deficits.
    /// Surplus days subtract.
    func totalDeficit(inMonthOf month: Date) -> Double? {
        let deficits = trackedDays(inMonthOf: month).map(\.deficitKcal)
        guard !deficits.isEmpty else { return nil }
        return deficits.reduce(0, +)
    }

    func daysTracked(inMonthOf month: Date) -> Int {
        trackedDays(inMonthOf: month).count
    }

    func totalCalories(inMonthOf month: Date) -> Double {
        trackedDays(inMonthOf: month).map(\.intakeKcal).reduce(0, +)
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
