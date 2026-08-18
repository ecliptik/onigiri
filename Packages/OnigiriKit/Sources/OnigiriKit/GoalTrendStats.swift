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
    /// What the scale implies you actually burn, kcal/day — see
    /// `ObservedBurn`. nil until the window carries enough tracked days
    /// to mean anything. REPORTED ONLY: nothing plans from it.
    public let observedBurnKcal: Double?
    /// Mean MEASURED burn over the very same tracked days, so the two
    /// can be subtracted honestly. Reading the observed figure against
    /// `averageBurnKcal` instead would compare across two different
    /// windows and attribute the difference to the model.
    public let measuredBurnKcal: Double?
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
    /// The same projection with `paceBoostKcalPerDay` more deficit a day
    /// — the finish date as a CHOICE rather than a forecast to watch.
    /// Same fit, same grid, same three-year cutoff; only the slope
    /// changes. nil without a base projection, and nil when the boost
    /// doesn't move the answer off its bucket — an identical pair of
    /// dates offered as an incentive is worse than saying nothing.
    public let fasterWindow: ClosedRange<Date>?
    /// Maintenance's counterpart to the projection: the same fit's
    /// slope as lb/week, signed (negative = losing). nil outside
    /// maintenance or under the same weigh-in-span gate.
    public let driftLbPerWeek: Double?
    /// Net deficit actually banked across the TRACKED days on record,
    /// and the weight it implies. The number the scale can't argue with:
    /// a morning of water weight moves the chart, never this. Surplus
    /// days subtract — banked means net, or it's a scoreboard rather
    /// than a measure.
    ///
    /// Untracked days are excluded, and that exclusion is load-bearing:
    /// a day with burn and no logged food reads as a ~2,500 kcal deficit
    /// and would silently inflate this into fiction.
    public let bankedKcal: Double
    public let bankedLb: Double
    /// How many tracked days `bankedKcal` covers. Shown beside it
    /// because "Total deficit" otherwise reads as "since I set this
    /// goal", which it has never been (the user, 2026-08-08).
    public let bankedDays: Int
    /// Weigh-ins (and the target/anchor line, when one is set) padded
    /// by 2 lb.
    public let chartYDomain: ClosedRange<Double>

    /// |drift| below this reads "holding steady" rather than a trend —
    /// under the scale's own noise floor for a week-scale readout.
    public static let steadyDriftThresholdLbPerWeek = 0.15

    /// How much more daily deficit the "or you could" line offers. Small
    /// on purpose: a hundred kcal is one snack, an answer someone can
    /// act on tonight, where 500 would just restate the diet.
    public static let paceBoostKcalPerDay = 100.0

    public static let empty = GoalTrendStats(
        predicted30Lb: nil, actual30Lb: nil, projectedWindow: nil,
        fasterWindow: nil,
        driftLbPerWeek: nil, bankedKcal: 0, bankedLb: 0, bankedDays: 0, chartYDomain: 0...1
    )

    public init(
        predicted30Lb: Double?, actual30Lb: Double?,
        observedBurnKcal: Double? = nil, measuredBurnKcal: Double? = nil,
        projectedWindow: ClosedRange<Date>?,
        fasterWindow: ClosedRange<Date>? = nil,
        driftLbPerWeek: Double?,
        bankedKcal: Double = 0, bankedLb: Double = 0, bankedDays: Int = 0,
        chartYDomain: ClosedRange<Double>
    ) {
        self.predicted30Lb = predicted30Lb
        self.actual30Lb = actual30Lb
        self.observedBurnKcal = observedBurnKcal
        self.measuredBurnKcal = measuredBurnKcal
        self.projectedWindow = projectedWindow
        self.fasterWindow = fasterWindow
        self.driftLbPerWeek = driftLbPerWeek
        self.bankedKcal = bankedKcal
        self.bankedLb = bankedLb
        self.bankedDays = bankedDays
        self.chartYDomain = chartYDomain
    }

    public static func derive(
        weightHistory: [WeightTrend.Point],
        dailyTotals: [DayEnergyTotals],
        targetWeightLb: Double?,
        isMaintenance: Bool,
        untrackedBelowKcal: Double = 0,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> GoalTrendStats {
        // Tracked days only — see bankedKcal.
        let trackedDays = dailyTotals
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: untrackedBelowKcal) }
        let banked = trackedDays.reduce(0) { $0 + $1.deficitKcal }
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        // Nil until the window has logged days — no data, no claim.
        //
        // TRACKED days only, the same gate `banked` applies, and for the
        // same reason its doc calls load-bearing: a day with burn and no
        // logged food reads as a ~2,500 kcal deficit. Unfiltered, one
        // such day inflates "predicted" by most of a pound of fiction —
        // and this row's whole job is to be compared against the scale,
        // so the fiction lands as "the scale is lagging" when really the
        // prediction was never earned (2026-08-08). `banked` guarded
        // this from the start; this line simply never did.
        let deficits = trackedDays
            .filter { $0.day >= thirtyDaysAgo }
            .map(\.deficitKcal)
        let predicted = deficits.isEmpty
            ? nil
            : WeightTrend.Change.predictedLb(totalDeficitKcal: deficits.reduce(0, +))
        let actual = WeightTrend.Change.actualLb(history: weightHistory, from: thirtyDaysAgo, to: now)

        // What the scale says the burn really was, beside what was
        // measured — the two read over the SAME tracked days, so their
        // difference is the model's error and not a window mismatch.
        // Reported, never planned from: see `ObservedBurn` for the five
        // causes this single number cannot tell apart, and for why
        // feeding it back into `dayBurn` would resurrect the deleted
        // trailing-average substitution.
        let windowDays = trackedDays.filter { $0.day >= thirtyDaysAgo }
        let observedBurn: Double? = {
            guard !windowDays.isEmpty,
                  let rate = WeightTrend.Change.actualRateLbPerDay(
                      history: weightHistory, from: thirtyDaysAgo, to: now)
            else { return nil }
            let meanIntake = windowDays.reduce(0) { $0 + $1.intakeKcal }
                / Double(windowDays.count)
            return ObservedBurn.kcalPerDay(
                meanDailyIntakeKcal: meanIntake,
                scaleRateLbPerDay: rate,
                trackedDays: windowDays.count
            )
        }()
        // Only alongside the observed figure — on its own it is a third
        // burn average on a screen that already carries two.
        let measuredBurn: Double? = observedBurn == nil || windowDays.isEmpty
            ? nil
            : windowDays.reduce(0) { $0 + $1.burnKcal } / Double(windowDays.count)

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
        var faster: ClosedRange<Date>?
        var drift: Double?
        if isMaintenance {
            drift = trendFit.map { $0.slopeLbPerDay * 7 }
        } else if let target = targetWeightLb, let fit = trendFit {
            projected = finishWindow(
                fit: fit, slopeLbPerDay: fit.slopeLbPerDay, target: target,
                from: now, calendar: calendar)
            // Pace as a choice. One more kcal/day of deficit is one more
            // lb/day off the slope, divided by the 3,500 the rest of the
            // app converts with — no new math, and the answer lands on
            // the same grid so it reads like its neighbour.
            if let projected {
                let boost = paceBoostKcalPerDay / WeightTrend.Change.kcalPerLb
                let sooner = finishWindow(
                    fit: fit, slopeLbPerDay: fit.slopeLbPerDay - boost, target: target,
                    from: now, calendar: calendar)
                // Only when it actually buys a different bucket.
                if let sooner, sooner.lowerBound < projected.lowerBound { faster = sooner }
            }
        }

        // The target line (lose) or hold-near anchor (maintenance)
        // belongs in the domain whenever it's drawn; 0 means no anchor.
        let anchor = (targetWeightLb ?? 0) > 0 ? targetWeightLb : nil
        // The DAILY LOWS set the scale, not the raw cloud. An evening
        // weigh-in runs 2–3 lb above that morning's reading, so sourcing
        // the axis from raw samples let the noisiest readings on record
        // decide how tall the chart was — and the trend the chart exists
        // to show got squashed by the spread around it (2026-08-14).
        let lows = WeightTrend.dailyLows(weightHistory, calendar: calendar).map(\.weightLb)
        let scaleSetting = lows + [anchor].compactMap(\.self)
        let domain: ClosedRange<Double>
        if let lo = scaleSetting.min(), let hi = scaleSetting.max() {
            var lower = lo - domainPadLb
            var upper = hi + domainPadLb
            // The raw cloud is still let in — points that clip read as
            // missing data — but only so far. One reading may push the
            // axis by a normal same-day rise past the lows, never more.
            let raw = weightHistory.map(\.weightLb)
            if let rawLo = raw.min(), let lowsLo = lows.min() {
                lower = min(lower, max(rawLo, lowsLo - WeightTrend.sameDayRiseLb))
            }
            if let rawHi = raw.max(), let lowsHi = lows.max() {
                upper = max(upper, min(rawHi, lowsHi + WeightTrend.sameDayRiseLb))
            }
            domain = lower...upper
        } else {
            domain = 0...1
        }
        return GoalTrendStats(
            predicted30Lb: predicted, actual30Lb: actual,
            observedBurnKcal: observedBurn, measuredBurnKcal: measuredBurn,
            projectedWindow: projected, fasterWindow: faster, driftLbPerWeek: drift,
            bankedKcal: banked, bankedLb: -WeightTrend.Change.predictedLb(totalDeficitKcal: banked),
            bankedDays: trackedDays.count,
            chartYDomain: domain
        )
    }

    /// When a given slope reaches the target, gated. Extracted so the
    /// trend answer and the with-more-deficit answer can't drift apart:
    /// both need the same "still above target", "actually descending"
    /// and "not past three years" rules to be comparable at all.
    private static func finishWindow(
        fit: WeightTrend.LinearFit, slopeLbPerDay: Double, target: Double,
        from now: Date, calendar: Calendar
    ) -> ClosedRange<Date>? {
        guard fit.currentLb > target, slopeLbPerDay < -0.01 else { return nil }
        let days = (fit.currentLb - target) / -slopeLbPerDay
        // A projection three years out is noise, not motivation.
        guard days < 365 * 3 else { return nil }
        return projectionWindow(daysOut: days, from: now, calendar: calendar)
    }

    /// How wide the finish window is, and the grid it snaps to.
    public static let projectionWindowDays = 5

    /// Breathing room above and below the series the chart is scaled to.
    static let domainPadLb = 2.0

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
