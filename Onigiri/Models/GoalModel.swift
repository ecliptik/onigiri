import Foundation
import OnigiriKit

/// The Goal tab's HealthKit reads and derived chart stats — the view
/// keeps only form state (target fields, focus, alerts). Same shape as
/// TodayModel/CalendarModel: the view asks, the model loads.
@Observable
final class GoalModel {
    private(set) var healthWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    /// Today's actual burn, floor for the plan's expected burn (the
    /// shared clamp — without it the preview lags Today on active days).
    private(set) var todayBurnKcal: Double = 0
    private(set) var weightHistory: [WeightTrend.Point] = []
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
        todayBurnKcal = ((try? await todayRead) ?? .zero).totalBurnKcal
        smoothedHistory = WeightTrend.movingAverage(weightHistory, windowDays: 7)
        lastLoaded = .now
    }

    /// Recompute the cached chart stats — when the HealthKit reads land
    /// and when the target/mode edits change what the chart derives from.
    func deriveTrendStats(targetWeightLb: Double?, isMaintenance: Bool) {
        trend = GoalTrendStats.derive(
            weightHistory: weightHistory,
            smoothedHistory: smoothedHistory,
            dailyTotals: dailyTotals,
            targetWeightLb: targetWeightLb,
            isMaintenance: isMaintenance
        )
    }
}
