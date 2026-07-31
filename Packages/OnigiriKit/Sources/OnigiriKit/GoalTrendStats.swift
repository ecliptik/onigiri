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
    /// When the target is reached at the recent trend — a recency-weighted
    /// least-squares fit over the last three weeks of weigh-ins
    /// (`WeightTrend.recencyWeightedFit`), so a diet started last week
    /// outweighs the flat weeks before it and twice-a-day weighers get
    /// the same window as once-a-day ones. nil in maintenance, without
    /// a target, a fitted current weight above the target, a meaningful
    /// downward slope, weigh-ins on 3+ days spanning a full week, or
    /// when the answer is over three years out (a projection that far
    /// is noise, not motivation).
    ///
    /// A WINDOW, not a day. The fit divides remaining pounds by a small
    /// noisy slope, so a single heavy morning moved the answer by a week
    /// — "that date can seem to change widely depending on the day" (the
    /// user, 2026-07-31). Two things settle it: the fit runs on the
    /// SMOOTHED series rather than raw weigh-ins, and the result is
    /// quantized to a 5-day grid, so ordinary scale noise doesn't move
    /// the dates on screen at all. Five days is deliberately narrow —
    /// wide enough to stop the flapping, tight enough to still answer
    /// the question.
    public let projectedWindow: ClosedRange<Date>?
    /// Maintenance's counterpart to the projection: the same fit's
    /// slope as lb/week, signed (negative = losing). nil outside
    /// maintenance or under the same weigh-in-span gate.
    public let driftLbPerWeek: Double?
    /// Weigh-ins (and the target/anchor line, when one is set) padded
    /// by 2 lb.
    public let chartYDomain: ClosedRange<Double>

    /// |drift| below this reads "holding steady" rather than a trend —
    /// under the scale's own noise floor for a week-scale readout.
    public static let steadyDriftThresholdLbPerWeek = 0.15

    public static let empty = GoalTrendStats(
        predicted30Lb: nil, actual30Lb: nil, projectedWindow: nil,
        driftLbPerWeek: nil, chartYDomain: 0...1
    )

    public init(
        predicted30Lb: Double?, actual30Lb: Double?,
        projectedWindow: ClosedRange<Date>?, driftLbPerWeek: Double?,
        chartYDomain: ClosedRange<Double>
    ) {
        self.predicted30Lb = predicted30Lb
        self.actual30Lb = actual30Lb
        self.projectedWindow = projectedWindow
        self.driftLbPerWeek = driftLbPerWeek
        self.chartYDomain = chartYDomain
    }

    public static func derive(
        weightHistory: [WeightTrend.Point],
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
        let actual = WeightTrend.Change.actualLb(history: weightHistory, from: thirtyDaysAgo, to: now)

        // One fit powers both modes: lose projects a finish window from
        // it, maintenance reads it as drift.
        //
        // Fitting the SMOOTHED series was tried and REJECTED (2026-07-31):
        // it steadies the answer but erases real trend changes with it —
        // the fresh-diet fixture (a flat week, then a week of losing)
        // went from a 37–44 day answer to 59–64, because a trailing
        // average drags the plateau into the slope. Damping noise is
        // worth doing; damping the signal is not. Stability comes from
        // the window instead.
        let trendStart = calendar.date(byAdding: .day, value: -21, to: now)
        let recent = trendStart.map { start in weightHistory.filter { $0.date >= start } } ?? []
        let trendFit = hasProjectableSpan(recent, calendar: calendar)
            ? WeightTrend.recencyWeightedFit(recent, reference: now)
            : nil

        var projected: ClosedRange<Date>?
        var drift: Double?
        if isMaintenance {
            drift = trendFit.map { $0.slopeLbPerDay * 7 }
        } else if let target = targetWeightLb, let fit = trendFit,
                  fit.currentLb > target, fit.slopeLbPerDay < -0.01 {
            let days = (fit.currentLb - target) / -fit.slopeLbPerDay
            if days < 365 * 3 {
                projected = projectionWindow(daysOut: days, from: now, calendar: calendar)
            }
        }

        // The target line (lose) or hold-near anchor (maintenance)
        // belongs in the domain whenever it's drawn; 0 means no anchor.
        let anchor = (targetWeightLb ?? 0) > 0 ? targetWeightLb : nil
        let weights = weightHistory.map(\.weightLb) + [anchor].compactMap(\.self)
        let domain: ClosedRange<Double>
        if let lo = weights.min(), let hi = weights.max() {
            domain = (lo - 2)...(hi + 2)
        } else {
            domain = 0...1
        }
        return GoalTrendStats(
            predicted30Lb: predicted, actual30Lb: actual,
            projectedWindow: projected, driftLbPerWeek: drift, chartYDomain: domain
        )
    }

    /// How wide the finish window is, and the grid it snaps to.
    public static let projectionWindowDays = 5

    /// The finish window containing `daysOut`, snapped to a fixed grid.
    /// Snapping is what makes it hold still: an estimate that wanders
    /// from 8 days to 9 to 7 stays inside one bucket and the screen
    /// never changes. Only a real move crosses a boundary.
    static func projectionWindow(
        daysOut: Double, from now: Date, calendar: Calendar
    ) -> ClosedRange<Date>? {
        let day = max(0, Int(daysOut.rounded()))
        let bucket = (day / projectionWindowDays) * projectionWindowDays
        guard let start = calendar.date(
                byAdding: .day, value: bucket, to: calendar.startOfDay(for: now)),
              let end = calendar.date(
                byAdding: .day, value: projectionWindowDays, to: start)
        else { return nil }
        return start...end
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
