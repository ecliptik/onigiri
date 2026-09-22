import Foundation
import OnigiriKit

/// The Goal tab's HealthKit reads and derived chart stats — the view
/// keeps only form state (target fields, focus, alerts). Same shape as
/// TodayModel/CalendarModel: the view asks, the model loads.
@Observable
final class GoalModel {
    private(set) var healthWeightLb: Double?
    /// The weight the deficit target is derived from (the user's
    /// WeightBasis). nil until loaded; callers fall back to
    /// healthWeightLb.
    var basisWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    private(set) var weightHistory: [WeightTrend.Point] = []
    /// Full-day resting from Health's body metrics — the floor under
    /// every day's resting credit, shown on the Goal screen because it
    /// is now half of what the budget is made of.
    private(set) var estimatedRestingKcal: Double?
    private(set) var dailyTotals: [DayEnergyTotals] = []
    /// Cached 7-day smoothing of weightHistory — smoothed once per
    /// load, not per keystroke (typing a target re-evaluates the view
    /// body per digit, and each evaluation used to re-average ~90
    /// points and re-fit the slope).
    ///
    /// Averaged over the DAILY LOWS, not the raw samples. It was the
    /// only weight series in the app derived from raw readings, so the
    /// line the eye reads ended ~2 lb above the number the budget plans
    /// from, a line drawn ~2 lb above both the last weigh-in and the basis
    /// (the user, 2026-08-14) — and a day weighed twice pulled it up
    /// more than a day weighed once, which measures weighing habits
    /// rather than body mass (`WeightTrend.dailyLows`). Its last point
    /// now equals `WeightTrend.targetBasisLb`, which is the property
    /// `GoalFinishLineTests` pins.
    private(set) var smoothedHistory: [WeightTrend.Point] = []
    /// Timestamps of the readings that were their day's low — so the
    /// scatter can draw the rest of the cloud back without pretending
    /// every dot carries equal weight. A Set because the chart iterates
    /// the raw history and asks per point.
    private(set) var dailyLowDates: Set<Date> = []
    /// The chart's derived numbers, cached for the same reason.
    private(set) var trend = GoalTrendStats.empty
    /// False until the first load has ANSWERED. Until then a nil weight
    /// and an empty history mean "not asked yet", not "Health has none" —
    /// and GoalView used to print the second reading as fact for the
    /// length of the first load: "No weight in Apple Health yet — enter
    /// it here." over a manual field, and the no-chart text, both
    /// replaced a beat later with a layout jump (2026-09-17; Today's
    /// zeros-as-facts, on the next tab over).
    private(set) var hasLoaded = false
    /// The first frame's numbers came from `GoalPrimeStore` — what Health
    /// said last time, not yet confirmed this launch. The view draws
    /// primed and loaded alike (`hasContent`); only a screen with NEITHER
    /// shows placeholders. Save waits for `hasLoaded` regardless: a prime
    /// is a picture, and nothing is written from a picture.
    private(set) var isPrimed = false
    /// Something real to draw: a prime, or Health's own answer.
    var hasContent: Bool { hasLoaded || isPrimed }
    /// Staleness gate for the loads (see loadIfStale).
    private var refreshGate = RefreshGate()

    private let health = HealthKitService()

    @ObservationIgnored private var primeChecked = false

    /// Called from the view's `.onAppear` — before the first frame, once.
    /// NOT from `init`: `GoalModel()` is a `@State`'s default value, which
    /// SwiftUI re-evaluates every time the view struct is rebuilt and
    /// then throws away, so work here would ride every `ContentView` body
    /// pass (the tab-bar lessons, `plans/PLAN-tab-bar-jank.md`). Nothing
    /// applied here is a fact until `loadIfStale()` says so.
    func applyLaunchPrimeIfNeeded() {
        guard !primeChecked else { return }
        primeChecked = true
        guard !hasLoaded, let prime = GoalPrimeStore.launchPrime else { return }
        healthWeightLb = prime.healthWeightLb
        averageBurnKcal = prime.averageBurnKcal
        estimatedRestingKcal = prime.estimatedRestingKcal
        weightHistory = prime.weightHistory
        dailyTotals = prime.dailyTotals
        deriveWeightSeries()
        isPrimed = true
    }

    /// Everything computed FROM the raw reads — one function, so a primed
    /// first frame and a live load cannot derive differently, and a prime
    /// is re-read under the settings in force now (`weightBasis`) rather
    /// than the ones it was saved under.
    private func deriveWeightSeries() {
        let lows = WeightTrend.dailyLows(weightHistory)
        dailyLowDates = Set(lows.map(\.date))
        smoothedHistory = WeightTrend.movingAverage(lows, windowDays: 7)
        // The weight the DEFICIT TARGET rides — free here, since the
        // history is already loaded. Kept SEPARATE from healthWeightLb:
        // the Weight field, validation and "use current as target" must
        // keep showing what the scale actually said.
        basisWeightLb = WeightTrend.basisLb(
            SharedStore.weightBasis, history: weightHistory, latestLb: healthWeightLb)
    }

    /// TabView re-runs the view's .task on every visit; a quick tab
    /// bounce shouldn't replay four HealthKit reads over 90-day windows
    /// (TodayModel's staleness rule). Day-roll still refreshes.
    /// Reload regardless of the staleness window — for a weigh-in that
    /// landed from outside the app while this tab was on screen. The
    /// window exists to stop a tab bounce replaying four 90-day reads;
    /// a real new sample is exactly what it must not suppress.
    func reload() async {
        refreshGate.reset()
        await loadIfStale()
    }

    /// Returns whether it actually refreshed — GoalView's `.task` uses
    /// this to skip `deriveTrendStats()` on a tab bounce that found
    /// nothing stale, instead of re-deriving the identical trend from
    /// the same in-memory arrays (and re-writing `trend`, which
    /// `@Observable` never skips for an equal value) on every visit
    /// (2026-09-15; same missing-gate shape as `TodayModel.start()`).
    @discardableResult
    func loadIfStale() async -> Bool {
        guard refreshGate.isStale(maxAge: 30) else { return false }
        #if DEBUG
        // UI-test hook (`testGoalFirstVisitShowsNoCancel`): holds this
        // load open so anything that wrongly WAITS on it stays wrong long
        // enough to be seen. The Cancel flash it guards lasted ~100 ms on
        // a simulator, far inside XCUITest's query latency.
        if ProcessInfo.processInfo.arguments.contains("--slow-goal-load") {
            try? await Task.sleep(for: .seconds(4))
        }
        #endif
        // Independent reads — concurrent, not serial (the trend chart
        // used to populate a query-chain late).
        async let weightRead = health.latestBodyMassLb()
        async let burnRead = health.averageDailyBurnKcal()
        async let historyRead = health.bodyMassHistory()
        async let totalsRead = health.dailyEnergyTotals(
            burnCorrectionKcal: SharedStore.burnCorrectionKcal)
        healthWeightLb = (try? await weightRead) ?? nil
        averageBurnKcal = (try? await burnRead) ?? nil
        weightHistory = (try? await historyRead) ?? []
        dailyTotals = (try? await totalsRead) ?? []
        deriveWeightSeries()
        let body = await health.bodyProfile()
        // `basisWeightLb`, not `healthWeightLb`. This estimate is what
        // `Resting budget` is cut from and what floors every day's
        // resting credit — a verdict-shaped number, so it runs on the
        // sustained basis like every other one. Reading the raw
        // weigh-in here let an evening reading raise Goal's budget while
        // Today's (floored from `targetBasisWeightLb`) held still: ~14
        // kcal at 3 lb, since the equation's weight term is 10 kcal/kg,
        // but off the very reading the basis exists to discard
        // (2026-08-16). The Weight field and validation still show
        // `healthWeightLb` — those report a measurement.
        estimatedRestingKcal = {
            guard let heightCm = body.heightCm, let age = body.ageYears,
                  let weightLb = basisWeightLb else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: body.sex)
        }()
        // No `todaySummary()` read any more. Goal carried today's burn,
        // intake and resting credit for the rows that reported a DAY,
        // and those moved to Today where the logging they track lives
        // (the user, 2026-08-23). Nothing on this screen changes during
        // a day now, so a per-visit day query bought nothing. The
        // `TodayBurnFloor` ratchet went with it — TodayView and
        // `DailyPlanLoader` still drive it, and this was only ever a
        // reader.
        refreshGate.markRefreshed()
        // Guarded: `@Observable` never skips an equal write.
        if !hasLoaded { hasLoaded = true }
        // The next cold launch's first frame. Only ever from a Health
        // answer, and the store refuses the empty one a sealed device
        // returns (`GoalPrime.isTrustworthy`).
        GoalPrimeStore.store(GoalPrime(
            savedAt: .now,
            healthWeightLb: healthWeightLb,
            averageBurnKcal: averageBurnKcal,
            estimatedRestingKcal: estimatedRestingKcal,
            weightHistory: weightHistory,
            dailyTotals: dailyTotals
        ))
        return true
    }

    /// Recompute the cached chart stats — when the HealthKit reads land
    /// and when the target/mode edits change what the chart derives from.
    func deriveTrendStats(targetWeightLb: Double?, isMaintenance: Bool) {
        trend = GoalTrendStats.derive(
            weightHistory: weightHistory,
            dailyTotals: dailyTotals,
            targetWeightLb: targetWeightLb,
            isMaintenance: isMaintenance,
            // The same threshold the calendar judges tracked days by, so
            // "banked" counts exactly the days that earned badges.
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
    }
}
