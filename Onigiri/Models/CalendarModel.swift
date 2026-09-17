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
    /// Whether the current goal is maintenance — days without a snapshot
    /// fall back to the current rule, so the fallback needs the mode.
    private(set) var isMaintenance = false
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

    /// Health has answered at least once this launch.
    private(set) var hasLoaded = false
    /// The first frame came from `CalendarPrimeStore` — the last
    /// refresh's raw days, re-judged now. The view draws primed and
    /// loaded alike (`hasContent`); with NEITHER, the month's counts are
    /// placeholders rather than a confident "0 days".
    private(set) var isPrimed = false
    var hasContent: Bool { hasLoaded || isPrimed }

    private let health = HealthKitService()
    private var summaryGeneration = 0

    @ObservationIgnored private var primeChecked = false

    /// Called from the view's `.onAppear` — before the first frame, once.
    /// NOT from `init`: `CalendarModel()` is a `@State`'s default value,
    /// re-evaluated and discarded on every rebuild of the view struct
    /// (see `GoalModel.applyLaunchPrimeIfNeeded`). RAW days only — every
    /// badge and the streak are re-derived here, against today, by the
    /// same `recomputeBadges()` a live refresh runs (`CalendarPrime`).
    func applyLaunchPrimeIfNeeded() {
        guard !primeChecked else { return }
        primeChecked = true
        guard !hasLoaded, let prime = CalendarPrimeStore.launchPrime else { return }
        let calendar = Calendar.current
        for total in prime.totals {
            totalsByDay[calendar.startOfDay(for: total.day)] = total
        }
        targetDeficitKcal = prime.targetDeficitKcal
        isMaintenance = prime.isMaintenance
        weightHistory = prime.weightHistory
        recomputeBadges()
        // The day card opens on TODAY, so its slots are primed only by a
        // card saved today — and the per-slot totals only if the slots
        // still track what they tracked then (`CalendarPrime.DayCard`).
        if let card = prime.dayCard, card.isValid() {
            selectedDaySummary = card.summary
            if let slots = card.slotTotals(ifReadAs: Self.slotKeys) {
                selectedDaySlotTotals = slots
            }
        }
        isPrimed = true
    }

    /// What each tracked slot is set to right now — the key a primed slot
    /// total must have been read under to mean anything.
    private static var slotKeys: [String] {
        [1, 2].map { SharedStore.trackedNutrient(slot: $0)?.key ?? SharedStore.trackedMetricNone }
    }

    /// The trailing window the last `refresh()` fetched, and the day the
    /// published summary belongs to — what `storePrime()` writes from.
    @ObservationIgnored private var windowTotals: [DayEnergyTotals] = []
    @ObservationIgnored private var summaryDay: Date?
    @ObservationIgnored private var summarySlotKeys: [String] = []

    /// The next cold launch's first frame. Called when EITHER half lands
    /// — the refresh or the day card's read, which run side by side — so
    /// whichever finishes last writes the complete picture. Only once
    /// Health has answered for the window; the store refuses the
    /// energy-less one a sealed device returns, and the day card rides
    /// along only for today, and only if it isn't a sealed zero.
    private func storePrime() {
        guard hasLoaded else { return }
        var card: CalendarPrime.DayCard?
        if let summaryDay, let summary = selectedDaySummary,
           Calendar.current.isDateInToday(summaryDay) {
            let candidate = CalendarPrime.DayCard(
                day: summaryDay, summary: summary,
                slotKeys: summarySlotKeys, slotTotals: selectedDaySlotTotals)
            if candidate.isTrustworthy { card = candidate }
        }
        CalendarPrimeStore.store(CalendarPrime(
            savedAt: .now,
            totals: windowTotals,
            targetDeficitKcal: targetDeficitKcal,
            isMaintenance: isMaintenance,
            weightHistory: weightHistory,
            dayCard: card
        ))
    }
    /// Foreground-gate stamp: once the tab has been visited it stays in
    /// the TabView hierarchy, so its scenePhase handler fired the full
    /// refresh (incl. a year of weigh-ins) on every app activation.
    private var refreshGate = RefreshGate()
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
        return healthChanged || refreshGate.isStale(maxAge: 60)
    }

    func refresh(goal: SyncedGoal?, forceWeights: Bool = false) async {
        #if DEBUG
        // UI-test hook (`testColdOpenPaintsTheLastLoad`), the twin of
        // GoalModel's `--slow-goal-load`: holds the first refresh open so
        // what the tab draws BEFORE Health answers can be looked at.
        if !hasLoaded, ProcessInfo.processInfo.arguments.contains("--slow-calendar-load") {
            try? await Task.sleep(for: .seconds(4))
        }
        #endif
        // Today's plan supplies the rule the calendar judges against.
        let plan = await DailyPlanLoader.load(goal: goal)
        targetDeficitKcal = plan.deficitTargetKcal
        isMaintenance = goal?.isMaintenance ?? false
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
        refreshGate.markRefreshed()
        // Guarded: `@Observable` never skips an equal write.
        if !hasLoaded { hasLoaded = true }
        // The window THIS refresh fetched, never the merged dictionary
        // (on-demand months are a session's browsing, not the month the
        // tab opens on).
        windowTotals = totals
        storePrime()
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
    /// snapshotted rule (falling back to today's), and days under the
    /// untracked threshold never qualify.
    private func recomputeBadges() {
        earned = StreakCalendar.earnedDays(
            totals: Array(totalsByDay.values),
            fallbackRule: .current(targetKcal: targetDeficitKcal, isMaintenance: isMaintenance),
            rulesByDay: DeficitTargetHistory.rulesByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        streak = StreakCalendar.currentStreak(earned: earned)
        bestStreak = StreakCalendar.bestStreak(earned: earned)
        let calendar = Calendar.current
        trackedDaySet = Set(totalsByDay.values
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: SharedStore.untrackedBelowKcal) }
            .map { calendar.startOfDay(for: $0.day) })
    }

    /// The deficit target a day is judged against — the ONE rule shared
    /// with Today (DeficitTargetHistory.judgingTarget): history by its
    /// own snapshot, the day in progress by the LIVE target. This used
    /// to read the snapshot for today too, so for the minute between a
    /// goal edit and the next re-stamp this card and Today's goal card
    /// could show two different targets for the same live day (audit,
    /// 2026-08-17).
    func targetDeficit(for day: Date) -> Double? {
        DeficitTargetHistory.judgingTarget(on: day, live: targetDeficitKcal)
    }

    /// Water total and eating-event count for the month detail.
    func loadMonthStats(for month: Date) async {
        monthWaterOz = nil
        monthFoodEntries = nil
        let stats = try? await health.monthStats(for: month)
        monthWaterOz = stats?.waterOz
        monthFoodEntries = stats?.foodEntryCount
    }

    /// The month-detail aggregates, computed in ONE pass over the
    /// month's tracked days — the four stand-alone methods this
    /// replaces each re-filtered totalsByDay per call, and the detail
    /// screen reads all of them per render (2026-07-16 audit).
    struct MonthStats {
        var daysTracked = 0
        var totalCalories = 0.0
        var totalBurned = 0.0
        /// Net deficit summed across TRACKED days (nil when none) —
        /// untracked days would skew it with phantom full-burn
        /// deficits. Surplus days subtract.
        var totalDeficit: Double?
        /// Predicted lb change for the month (its net deficit ÷ 3,500).
        var predictedLb: Double? { totalDeficit.map(WeightTrend.Change.predictedLb) }
    }

    func monthStats(inMonthOf month: Date) -> MonthStats {
        var stats = MonthStats()
        var deficit = 0.0
        for day in trackedDays(inMonthOf: month) {
            stats.daysTracked += 1
            stats.totalCalories += day.intakeKcal
            stats.totalBurned += day.burnKcal
            deficit += day.deficitKcal
        }
        if stats.daysTracked > 0 { stats.totalDeficit = deficit }
        return stats
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

    func earnedCount(inMonthOf month: Date) -> Int {
        StreakCalendar.earnedCount(inMonthOf: month, earned: earned)
    }

    /// Sodium/water for the selected day — the same numbers Today shows —
    /// plus the tracked-metric slot totals, under one generation guard so
    /// fast day-swiping can't pair one day's slots with another's summary.
    func loadDaySummary(for day: Date) async {
        summaryGeneration += 1
        let generation = summaryGeneration
        #if DEBUG
        // `--slow-calendar-load` holds this read open too: it runs beside
        // the refresh now, and would otherwise land inside the window the
        // cold-open test looks at and hide a missing prime.
        if !hasLoaded, ProcessInfo.processInfo.arguments.contains("--slow-calendar-load") {
            try? await Task.sleep(for: .seconds(4))
        }
        #endif
        // Read BEFORE the awaits: a Settings change mid-read must not
        // stamp the new key onto a total read under the old one.
        let keys = Self.slotKeys
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
        summaryDay = day
        summarySlotKeys = keys
        storePrime()
    }

    private func slotDayTotal(slot: Int, day: Date) async -> Double? {
        guard let nutrient = SharedStore.trackedNutrient(slot: slot),
              nutrient != .sodium, nutrient != .water else { return nil }
        return try? await health.dayTotal(of: nutrient, for: day)
    }

}
