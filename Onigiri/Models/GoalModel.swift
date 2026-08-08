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
    /// Today's own burn (`DayBudget.dayBurn`, day-ratcheted), floor for
    /// the projection — without it the preview lags Today on an active
    /// day. Ratcheted HERE, once per load, not in the view body: the
    /// floor writes as it reads, and a view body re-runs per keystroke.
    private(set) var todayDayBurnKcal: Double = 0
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
    private(set) var smoothedHistory: [WeightTrend.Point] = []
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
        async let todayRead = health.todaySummary()
        healthWeightLb = (try? await weightRead) ?? nil
        averageBurnKcal = (try? await burnRead) ?? nil
        weightHistory = (try? await historyRead) ?? []
        dailyTotals = (try? await totalsRead) ?? []
        let today = (try? await todayRead) ?? .zero
        smoothedHistory = WeightTrend.movingAverage(weightHistory, windowDays: 7)
        // The weight the DEFICIT TARGET rides — free here, since the
        // history is already loaded. Kept SEPARATE from healthWeightLb:
        // the Weight field, validation and "use current as target" must
        // keep showing what the scale actually said.
        basisWeightLb = WeightTrend.basisLb(
            SharedStore.weightBasis, history: weightHistory, latestLb: healthWeightLb)
        let body = await health.bodyProfile()
        estimatedRestingKcal = {
            guard let heightCm = body.heightCm, let age = body.ageYears,
                  let weightLb = healthWeightLb else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: body.sex)
        }()
        todayDayBurnKcal = TodayBurnFloor.ratcheted(
            DayBudget.dayBurn(
                activeKcal: today.activeBurnKcal,
                restingKcal: today.restingBurnKcal,
                estimatedRestingKcal: estimatedRestingKcal
            )
        )
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
