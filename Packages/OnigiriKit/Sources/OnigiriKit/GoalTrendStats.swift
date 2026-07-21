import Foundation

/// The Goal screen's derived chart numbers — predicted-vs-actual over
/// the trailing 30 days, the projected target date, and the chart's
/// y-domain. Pure math over already-loaded Health data, extracted from
/// the view so the projection rules are unit-testable (the WeightTrend
/// primitives were tested; their composition wasn't).
public struct GoalTrendStats: Equatable, Sendable {
    /// Weight change the trailing 30 days of deficits predict; nil when
    /// the window has no logged days (no data, no claim).
    public let predicted30Lb: Double?
    /// Smoothed scale movement over the same window.
    public let actual30Lb: Double?
    /// Date the target is reached at the recent trend — recency-weighted
    /// least-squares fit over the last three weeks of RAW weigh-ins
    /// (`WeightTrend.recencyWeightedFit`), so a diet started last week
    /// outweighs the flat weeks before it and twice-a-day weighers get
    /// the same window as once-a-day ones. nil without a target, a
    /// fitted current weight above the target, a meaningful downward
    /// slope, weigh-ins on 3+ days spanning a full week, or when the
    /// answer is over three years out (a projection that far is noise,
    /// not motivation).
    public let projectedDate: Date?
    /// Weigh-ins (and the target, when losing) padded by 2 lb.
    public let chartYDomain: ClosedRange<Double>

    public static let empty = GoalTrendStats(
        predicted30Lb: nil, actual30Lb: nil, projectedDate: nil, chartYDomain: 0...1
    )

    public init(
        predicted30Lb: Double?, actual30Lb: Double?,
        projectedDate: Date?, chartYDomain: ClosedRange<Double>
    ) {
        self.predicted30Lb = predicted30Lb
        self.actual30Lb = actual30Lb
        self.projectedDate = projectedDate
        self.chartYDomain = chartYDomain
    }

    public static func derive(
        weightHistory: [WeightTrend.Point],
        smoothedHistory: [WeightTrend.Point],
        dailyTotals: [DayEnergyTotals],
        targetWeightLb: Double?,
        isMaintenance: Bool,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> GoalTrendStats {
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        // Nil until the window has logged days — no data, no claim.
        let deficits = dailyTotals
            .filter { $0.day >= thirtyDaysAgo }
            .map(\.deficitKcal)
        let predicted = deficits.isEmpty
            ? nil
            : WeightTrend.Change.predictedLb(totalDeficitKcal: deficits.reduce(0, +))
        let actual = WeightTrend.Change.actualLb(smoothed: smoothedHistory, from: thirtyDaysAgo, to: now)

        var projected: Date?
        if let target = targetWeightLb,
           let trendStart = calendar.date(byAdding: .day, value: -21, to: now) {
            let recent = weightHistory.filter { $0.date >= trendStart }
            if hasProjectableSpan(recent, calendar: calendar),
               let fit = WeightTrend.recencyWeightedFit(recent, reference: now),
               fit.currentLb > target,
               fit.slopeLbPerDay < -0.01 {
                let days = (fit.currentLb - target) / -fit.slopeLbPerDay
                if days < 365 * 3 {
                    projected = calendar.date(byAdding: .day, value: Int(days.rounded(.up)), to: now)
                }
            }
        }

        let weights = weightHistory.map(\.weightLb)
            + (isMaintenance ? [] : [targetWeightLb].compactMap(\.self))
        let domain: ClosedRange<Double>
        if let lo = weights.min(), let hi = weights.max() {
            domain = (lo - 2)...(hi + 2)
        } else {
            domain = 0...1
        }
        return GoalTrendStats(
            predicted30Lb: predicted, actual30Lb: actual,
            projectedDate: projected, chartYDomain: domain
        )
    }

    /// A projection needs a real base under it: weigh-ins on at least
    /// three distinct days spanning at least a full week. Below that a
    /// weekend of scale readings would mint a goal date.
    private static func hasProjectableSpan(
        _ points: [WeightTrend.Point], calendar: Calendar
    ) -> Bool {
        guard let first = points.first?.date, let last = points.last?.date,
              last.timeIntervalSince(first) >= 7 * 86400
        else { return false }
        return Set(points.map { calendar.startOfDay(for: $0.date) }).count >= 3
    }
}
