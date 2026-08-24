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
    /// from — 212 drawn against a 209.8 weigh-in and a ~210.8 basis
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
    /// Staleness stamp for the loads (see loadIfStale).
    private var lastLoaded: Date?

    private let health = HealthKitService()

    /// TabView re-runs the view's .task on every visit; a quick tab
    /// bounce shouldn't replay four HealthKit reads over 90-day windows
    /// (TodayModel's staleness rule). Day-roll still refreshes.
    /// Reload regardless of the staleness window — for a weigh-in that
    /// landed from outside the app while this tab was on screen. The
    /// window exists to stop a tab bounce replaying four 90-day reads;
    /// a real new sample is exactly what it must not suppress.
    func reload() async {
        lastLoaded = nil
        await loadIfStale()
    }

    func loadIfStale() async {
        if let last = lastLoaded,
           Date.now.timeIntervalSince(last) < 30,
           Calendar.current.isDate(last, inSameDayAs: .now) {
            return
        }
        // Independent reads — concurrent, not serial (the trend chart
        // used to populate a query-chain late).
        async let weightRead = health.latestBodyMassLb()
        async let burnRead = health.averageDailyBurnKcal()
        async let historyRead = health.bodyMassHistory()
        async let totalsRead = health.dailyEnergyTotals()
        healthWeightLb = (try? await weightRead) ?? nil
        averageBurnKcal = (try? await burnRead) ?? nil
        weightHistory = (try? await historyRead) ?? []
        dailyTotals = (try? await totalsRead) ?? []
        let lows = WeightTrend.dailyLows(weightHistory)
        dailyLowDates = Set(lows.map(\.date))
        smoothedHistory = WeightTrend.movingAverage(lows, windowDays: 7)
        // The weight the DEFICIT TARGET rides — free here, since the
        // history is already loaded. Kept SEPARATE from healthWeightLb:
        // the Weight field, validation and "use current as target" must
        // keep showing what the scale actually said.
        basisWeightLb = WeightTrend.basisLb(
            SharedStore.weightBasis, history: weightHistory, latestLb: healthWeightLb)
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
        lastLoaded = .now
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
