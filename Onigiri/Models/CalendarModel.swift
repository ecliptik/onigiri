import Foundation
import OnigiriKit

@Observable
final class CalendarModel {
    private(set) var earned: Set<Date> = []
    /// Days that cleared the untracked threshold — the month grid marks
    /// tracked-but-missed differently from no-data days.
    private(set) var trackedDaySet: Set<Date> = []
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var targetDeficitKcal: Double?
    private(set) var totalsByDay: [Date: DayEnergyTotals] = [:]
    /// Full summary (sodium, water) for the selected day's detail card.
    private(set) var selectedDaySummary: DailyEnergySummary?
    /// The selected day's totals for non-sodium/water tracked slots
    /// (loaded with the summary; sodium/water ride the summary itself).
    private(set) var selectedDaySlotTotals: [Double?] = [nil, nil]
    /// A year of weigh-ins so any browsable month can show its scale change.
    private(set) var weightHistory: [WeightTrend.Point] = []
    /// Month-detail extras, loaded on push (nil while loading).
    private(set) var monthWaterOz: Double?
    private(set) var monthFoodEntries: Int?

    private let health = HealthKitService()
    private var summaryGeneration = 0
    /// Foreground-gate stamps: once the tab has been visited it stays in
    /// the TabView hierarchy, so its scenePhase handler fired the full
    /// refresh (incl. a year of weigh-ins) on every app activation.
    private var lastRefreshed: Date?
    private var lastWeightLoad: Date?
    private var seenHealthWriteVersion = 0
    /// Start of the preloaded trailing window; months before it load on
    /// demand (`ensureTotals`) so browsing far back isn't half-empty.
    private var windowStart: Date?
    private var loadedMonths: Set<Date> = []

    /// Whether a foreground refresh is due: stale, the day rolled over, or
    /// Health data changed while away (widget button, watch log). Records
    /// the version it judged — the caller refreshes whenever this is true.
    func shouldForegroundRefresh(healthWriteVersion: Int) -> Bool {
        let healthChanged = healthWriteVersion != seenHealthWriteVersion
        seenHealthWriteVersion = healthWriteVersion
        guard let lastRefreshed else { return true }
        return healthChanged
            || !Calendar.current.isDate(lastRefreshed, inSameDayAs: .now)
            || Date.now.timeIntervalSince(lastRefreshed) > 60
    }

    func refresh(goal: SyncedGoal?, forceWeights: Bool = false) async {
        // Today's plan supplies the deficit target the calendar judges against.
        let plan = await DailyPlanLoader.load(goal: goal)
        targetDeficitKcal = plan.deficitTargetKcal
        let totals = (try? await health.dailyEnergyTotals()) ?? []
        let calendar = Calendar.current
        windowStart = calendar.date(byAdding: .day, value: -92, to: calendar.startOfDay(for: .now))
        // Merge (not replace): keep months loaded on demand while the
        // trailing window refreshes.
        for total in totals {
            totalsByDay[calendar.startOfDay(for: total.day)] = total
        }
        recomputeBadges()
        // The year of weigh-ins moves a few times a day at most — reload
        // it hourly on the passive paths, always on an explicit
        // pull-to-refresh (forceWeights).
        if forceWeights || weightHistory.isEmpty
            || lastWeightLoad.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true {
            weightHistory = (try? await health.bodyMassHistory(days: 365)) ?? weightHistory
            lastWeightLoad = .now
        }
        lastRefreshed = .now
    }

    /// Load a browsed month that predates the trailing window, once —
    /// energy totals for the badges/stats, and weigh-ins so "Scale
    /// change" doesn't hit the year-of-history cliff.
    func ensureTotals(forMonthOf month: Date) async {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return }
        guard let windowStart, monthStart < windowStart,
              !loadedMonths.contains(monthStart) else { return }
        guard let totals = try? await health.dailyEnergyTotals(
            from: monthStart, to: min(monthEnd, .now)
        ) else { return }
        loadedMonths.insert(monthStart)
        for total in totals {
            totalsByDay[calendar.startOfDay(for: total.day)] = total
        }
        recomputeBadges()
        if let weights = try? await health.bodyMassHistory(from: monthStart, to: min(monthEnd, .now)),
           !weights.isEmpty {
            // Merge and de-dupe (the trailing-365 load may overlap).
            let known = Set(weightHistory.map(\.date))
            weightHistory = (weightHistory + weights.filter { !known.contains($0.date) })
                .sorted { $0.date < $1.date }
        }
    }

    /// Badges are awarded when a day completes, judged by that day's
    /// snapshotted target (falling back to today's), and days under the
    /// untracked threshold never qualify.
    private func recomputeBadges() {
        earned = StreakCalendar.earnedDays(
            totals: Array(totalsByDay.values),
            targetDeficitKcal: targetDeficitKcal,
            targetsByDay: DeficitTargetHistory.targetsByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        streak = StreakCalendar.currentStreak(earned: earned)
        bestStreak = StreakCalendar.bestStreak(earned: earned)
        let calendar = Calendar.current
        trackedDaySet = Set(totalsByDay.values
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: SharedStore.untrackedBelowKcal) }
            .map { calendar.startOfDay(for: $0.day) })
    }

    /// The deficit target a day is judged against: its snapshot when one
    /// was recorded, else today's target.
    func targetDeficit(for day: Date) -> Double? {
        DeficitTargetHistory.target(on: day) ?? targetDeficitKcal
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

    /// Sodium/water for the selected day — the same numbers Today shows —
    /// plus the tracked-metric slot totals, under one generation guard so
    /// fast day-swiping can't pair one day's slots with another's summary.
    func loadDaySummary(for day: Date) async {
        summaryGeneration += 1
        let generation = summaryGeneration
        async let summaryRead = health.daySummary(for: day)
        // Non-sodium/water slots need their own day query; nil (slot off,
        // sodium/water, or a failed read) renders as "—", never a fake 0.
        // The slot reads are independent — run them concurrently.
        async let slot1 = slotDayTotal(slot: 1, day: day)
        async let slot2 = slotDayTotal(slot: 2, day: day)
        let slots = await [slot1, slot2]
        let summary = try? await summaryRead
        guard generation == summaryGeneration else { return }
        selectedDaySummary = summary
        selectedDaySlotTotals = slots
    }

    private func slotDayTotal(slot: Int, day: Date) async -> Double? {
        guard let nutrient = SharedStore.trackedNutrient(slot: slot),
              nutrient != .sodium, nutrient != .water else { return nil }
        return try? await health.dayTotal(of: nutrient, for: day)
    }

}
