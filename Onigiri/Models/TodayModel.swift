import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var foodLog: [FoodLogEntry] = []
    /// The food log pre-grouped by meal slot, computed once per refresh so
    /// the Today view never re-filters the whole day on a re-render (the
    /// per-category `.filter` in the body used to rerun on every unrelated
    /// state change — see the scroll-perf pass).
    private(set) var foodByCategory: [FoodCategory: [FoodLogEntry]] = [:]
    private(set) var waterLog: [WaterLogEntry] = []
    /// Day totals for the two configurable tracked-metric slots, in each
    /// nutrient's label unit (sodium/water reuse the summary's numbers).
    private(set) var trackedTotals: [Double] = [0, 0]
    private(set) var currentWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    /// Full-day resting energy from body metrics — the floor under the
    /// day's resting credit, so resting is available UP FRONT instead of
    /// dripping in hourly (2026-08-02). nil when Health lacks height or
    /// date of birth, in which case measured resting stands alone.
    private(set) var estimatedRestingKcal: Double?
    /// The burn the whole screen judges this day by (`DayBudget.dayBurn`,
    /// day-ratcheted for today) — the budget, the Net row, the goal
    /// card. Health's raw `summary.totalBurnKcal` stays what the Burned
    /// flank and the Active/Resting rows report: those state a
    /// measurement, this one reaches a verdict.
    private(set) var dayBurnKcal: Double = 0
    /// The day's deficit on that figure, positive for a deficit.
    var deficitKcal: Double {
        DayBudget.deficit(intakeKcal: summary.intakeKcal, dayBurnKcal: dayBurnKcal)
    }
    /// The resting the day was CREDITED — measured, floored by the
    /// body-metric estimate. This is the number inside the budget, and
    /// printing the measured one beside it was what made Details
    /// impossible to reconcile: a budget of 1,585 over a resting row
    /// reading 1,272, with the 1,830 it was actually built on nowhere on
    /// the screen (the user, 2026-08-02).
    var creditedRestingKcal: Double {
        max(summary.restingBurnKcal, estimatedRestingKcal ?? 0)
    }
    /// Smoothed scale movement over the past 7 days (negative = down);
    /// nil until Health holds enough weigh-ins to say.
    private(set) var weeklyTrendLb: Double?
    /// Weigh-ins behind that trend, kept rather than discarded so the
    /// goal-reached card can ask `GoalCompletion` whether the target has
    /// actually been reached. The read was already happening; only the
    /// window widened (to `GoalCompletion.maximumWindowDays`, since the
    /// criterion reaches that far back for a sparse weigher), and
    /// `Change.actualLb` windows to its own 7 days regardless.
    private(set) var weightHistory: [WeightTrend.Point] = []
    private(set) var errorMessage: String?
    /// Health write access explicitly denied — every log would fail
    /// with an opaque toast, so Today shows a recovery hint instead.
    private(set) var healthWriteDenied = false
    private(set) var selectedDate = Calendar.current.startOfDay(for: .now)

    private let health = HealthKitService()
    private var started = false
    /// Refreshes fire concurrently (task/appear/foreground/day swipes); only
    /// the newest may publish, or a slow old day overwrites the current one.
    private var refreshGeneration = 0
    /// Completed-load stamps for the foreground gate: quick app switches
    /// used to replay the full query set on every activation.
    private var lastRefreshed: Date?
    private var lastStaticLoad: Date?
    /// The ToastCenter.healthWriteVersion this model last refreshed
    /// against — a bump while backgrounded (widget button, watch log)
    /// must beat the staleness gate.
    private var seenHealthWriteVersion = 0

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Tracks intent, not the date: once midnight passes, `isToday` is
    /// already false for the day the user was pinned to, so only this
    /// flag can tell "left on today overnight" (roll forward) apart from
    /// "deliberately browsing yesterday" (stay put).
    private var followsToday = true

    func goToPreviousDay() async {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = previous
        followsToday = false
        await refresh()
    }

    func goToNextDay() async {
        guard !isToday,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        selectedDate = min(next, Calendar.current.startOfDay(for: .now))
        followsToday = isToday
        await refresh()
    }

    /// Jump straight to a day (date picker, Calendar's "View day").
    func select(day: Date) async {
        selectedDate = min(
            Calendar.current.startOfDay(for: day),
            Calendar.current.startOfDay(for: .now)
        )
        followsToday = isToday
        await refresh()
    }


    /// One-time startup: prompt for HealthKit access if never asked, then load.
    /// The view's .task can re-fire on tab switches — only run once.
    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        guard HealthKitService.isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        var seeding = false
        #if DEBUG
        seeding = ProcessInfo.processInfo.arguments.contains("--seed-sample-data")
        #endif
        do {
            #if DEBUG
            if seeding {
                // One combined sheet covering the seeder's extra types too.
                try await health.requestDebugSeedAuthorization()
            }
            #endif
            if !seeding, try await health.shouldRequestAuthorization() {
                try await health.requestAuthorization()
            }
        } catch {
            errorMessage = "Health authorization failed: \(error.localizedDescription)"
        }
        #if DEBUG
        if seeding {
            do {
                try await health.seedSampleData()
                print("[onigiri] seed: saved OK")
            } catch {
                errorMessage = "Seeding failed: \(error.localizedDescription)"
                print("[onigiri] seed FAILED: \(error)")
            }
        }
        #endif
        await loadStatic()
        await refresh()
        #if DEBUG
        // One line per launch per day: merged vs per-source vs plain
        // samples vs correlations, with timings. Yesterday comes along
        // because a fresh morning has nothing logged yet, and the
        // discrepancy this exists to measure only shows on a day that
        // actually has a watch-logged entry.
        // -2 keeps Aug 4 in view while it is still the only day with a
        // reproducible gap; drop back to [0, -1] once that is settled.
        for offset in [0, -1, -2] {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            print("[onigiri] day\(offset) \(await health.diagnoseIntake(for: day))")
        }
        print("[onigiri] \(await DailyPlanLoader.diagnose(goal: WatchSync.loadGoal()))")
        // Durable, unlike os_log — see WidgetBurnGate.note.
        for line in WidgetBurnGate.planJournal() {
            print("[onigiri] plan \(line)")
        }
        for line in WidgetBurnGate.journal() {
            print("[onigiri] burn \(line)")
        }
        #endif
    }

    /// Foreground (scenePhase) entry point: skip the query storm when the
    /// data is fresh — unless the calendar day rolled over (which must
    /// always re-anchor the view) or Health data changed while away
    /// (widget button, watch log — `healthWriteVersion` moved). The
    /// write-denied hint re-checks every time (a local status read).
    func foregrounded(healthWriteVersion: Int) async {
        healthWriteDenied = health.sharingDenied()
        let now = Date.now
        let dayRolled = lastRefreshed.map {
            !Calendar.current.isDate($0, inSameDayAs: now)
        } ?? true
        let healthChanged = healthWriteVersion != seenHealthWriteVersion
        if dayRolled || lastStaticLoad.map({ now.timeIntervalSince($0) > 300 }) ?? true {
            await loadStatic()
        }
        if dayRolled || healthChanged
            || lastRefreshed.map({ now.timeIntervalSince($0) > 30 }) ?? true {
            seenHealthWriteVersion = healthWriteVersion
            await refresh()
        }
    }

    /// Weight and average burn don't depend on the browsed day — loading
    /// them per chevron tap made day switching feel laggy. Fetched on
    /// start and on foregrounding instead.
    func loadStatic() async {
        // Independent reads — run them concurrently.
        // The deficit-target BASIS, not the raw last weigh-in — Today's
        // deficit has to match the widget's, and both ride this. The
        // resting estimate below uses the same value so one screen never
        // mixes two "current weights" (PLAN-target-weight-basis).
        async let weightRead = health.targetBasisWeightLb()
        async let burnRead = health.averageDailyBurnKcal()
        async let historyRead = health.bodyMassHistory(days: GoalCompletion.maximumWindowDays)
        currentWeightLb = (await weightRead) ?? currentWeightLb
        averageBurnKcal = (try? await burnRead) ?? averageBurnKcal
        let body = await health.bodyProfile()
        estimatedRestingKcal = {
            guard let heightCm = body.heightCm, let age = body.ageYears,
                  let weightLb = currentWeightLb else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm,
                ageYears: age, sex: body.sex)
        }()
        // The week's change comes from a linear fit over the raw
        // weigh-ins in the window — no smoothing, so no extra runway.
        if let history = try? await historyRead {
            weightHistory = history
            weeklyTrendLb = WeightTrend.Change.actualLb(
                history: history,
                from: Date.now.addingTimeInterval(-7 * 86400),
                to: .now
            )
        }
        // Re-checked on every foreground: the user may have just flipped
        // access in the Health app.
        healthWriteDenied = health.sharingDenied()
        lastStaticLoad = .now
    }

    /// Day data only — fast enough that browsing feels immediate.
    func refresh() async {
        // A new calendar day rolls the view forward to the new "today" —
        // unless the user deliberately navigated to a past day.
        if followsToday {
            selectedDate = Calendar.current.startOfDay(for: .now)
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            // Aligned: burn read from the same day-bucketed source the
            // calendar and badges use, so the two screens can't disagree
            // about the same day.
            async let summary = health.alignedDaySummary(for: selectedDate)
            async let foodLog = health.foodEntries(on: selectedDate)
            async let waterLog = health.waterEntries(on: selectedDate)
            async let tracked1 = trackedTotal(slot: 1)
            async let tracked2 = trackedTotal(slot: 2)
            // Cost of this read set, measured on device 2026-08-04 after
            // the totals moved to correlations: ~40 ms warm (~450 ms on
            // the first read of a launch, which is HealthKit waking up,
            // not us). `daySummary` traded THREE statistics queries for
            // one correlation query, so the refresh went from six queries
            // to five — the duplicated correlation fetch (one for this
            // list, one for the summary) rides along concurrently and a
            // correlation query measured 34 ms against 15 ms for a
            // statistics one. Not worth coalescing; don't "optimize" it
            // without measuring again.
            let (loadedSummary, loadedFood, loadedWater, loaded1, loaded2) =
                try await (summary, foodLog, waterLog, tracked1, tracked2)
            guard generation == refreshGeneration else { return }
            self.summary = loadedSummary
            self.foodLog = loadedFood
            self.foodByCategory = Dictionary(grouping: loadedFood, by: \.category)
            self.waterLog = loadedWater
            // Sodium/water ride the summary — no second query, and the
            // numbers can't disagree with the rest of the screen.
            self.trackedTotals = [
                loaded1 ?? slotSummaryValue(slot: 1, from: loadedSummary),
                loaded2 ?? slotSummaryValue(slot: 2, from: loadedSummary),
            ]
            // ONE burn figure for the whole screen, computed once here
            // rather than per view body: TodayBurnFloor WRITES as it
            // reads, and a body re-runs on every unrelated state change.
            let measured = DayBudget.dayBurn(
                activeKcal: loadedSummary.activeBurnKcal,
                restingKcal: loadedSummary.restingBurnKcal,
                estimatedRestingKcal: estimatedRestingKcal
            )
            // Ratcheted for TODAY only: Health revising burn down
            // (watch↔phone sample reconciliation) must not move the
            // budget against the user mid-day, and the floor's mark is
            // keyed to today — feeding it a browsed day's burn wrote
            // that day's number into today's floor (2026-07-30).
            dayBurnKcal = isToday ? TodayBurnFloor.ratcheted(measured) : measured
            lastRefreshed = .now
        } catch {
            guard generation == refreshGeneration else { return }
            // Transient read failures toast like every other transient
            // failure; errorMessage stays for the persistent start()
            // states (Health unavailable, authorization failed).
            ToastCenter.shared.show("Couldn't read Health data: \(error.localizedDescription)")
            print("[onigiri] refresh FAILED: \(error)")
        }
    }

    /// Nil for sodium/water — the caller reuses the day summary's values.
    private func trackedTotal(slot: Int) async throws -> Double? {
        switch SharedStore.trackedNutrient(slot: slot) {
        case nil: return 0 // slot is off — nothing to fetch
        case .sodium?, .water?: return nil
        case .some(let nutrient): return try await health.dayTotal(of: nutrient, for: selectedDate)
        }
    }

    private func slotSummaryValue(slot: Int, from summary: DailyEnergySummary) -> Double {
        switch SharedStore.trackedNutrient(slot: slot) {
        case .sodium?: summary.sodiumMg
        case .water?: summary.waterOz
        default: 0
        }
    }
}
