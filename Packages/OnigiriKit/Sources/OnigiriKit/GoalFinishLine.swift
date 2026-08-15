import Foundation

/// Where a lose goal stands against the scale — the ONE answer behind
/// the Goal screen's target section.
///
/// Before this existed the screen asked two unrelated questions and left
/// the reader to reconcile them: `GoalUpsert.validate` compared the
/// target to the RAW last weigh-in, while the celebration compared it to
/// the sustained basis. On 2026-08-14 a 209.8 lb morning against a 210 lb
/// target produced both at once — an orange "Target must be below your
/// current weight." beside a full progress bar reading 8.9 of 8.7 lb,
/// beside a projection promising the target in five days, and no
/// celebration anywhere, because the seven-day basis was still above 210.
/// Three different "now"s on one screen, none of them labelled.
///
/// So: one type, one weight — `GoalCompletion`'s sustained basis, the
/// same mean of daily lows the budget plans from. `reached` IS
/// `GoalCompletion.isMet`, not a second opinion about it.
///
/// The middle state is the point. "Under way" and "reached" are not
/// enough vocabulary for the last week of a goal, and without a word for
/// it the app rendered an arrival as a form error.
public enum GoalFinishLine: Equatable, Sendable {
    /// Still working: the basis is `bandLb` or more above the target.
    case underWay
    /// Inside the last pound. `remainingLb` is always positive — at or
    /// below the target with enough weigh-in days behind it is
    /// `reached`, not this.
    case approaching(basisLb: Double, remainingLb: Double)
    /// Met on the sustained rule. Carries the reading, so a caller can
    /// say which window answered without evaluating it twice.
    case reached(GoalCompletion)

    /// How close to the target reads as "there".
    ///
    /// Not a scale-noise figure: the basis is a seven-day mean of daily
    /// lows, so its own noise is well under a pound. This is the
    /// distance at which "0.4 lb to go" stops being a plan and starts
    /// being a rounding error.
    ///
    /// It is also what takes the cliff out of the budget.
    /// `requiredDailyDeficit` is `3500 / daysRemaining` kcal per pound —
    /// 194 kcal/day at 18 days out — so without a band the final pound
    /// swings the day's allowance by a snack on water weight, and then
    /// drops to zero the moment the mean happens to cross. Inside the
    /// band the deficit is simply 0, which is what the same arithmetic
    /// arrives at a morning later anyway.
    public static let bandLb = 1.0

    public var isReached: Bool {
        if case .reached = self { return true }
        return false
    }

    /// The finish line is in sight — the states that offer "keep going"
    /// rather than a plan to follow.
    public var isAtOrNearTarget: Bool {
        switch self {
        case .underWay: false
        case .approaching, .reached: true
        }
    }

    public static func evaluate(
        targetLb: Double,
        history: [WeightTrend.Point],
        bandLb: Double = bandLb,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalFinishLine {
        guard targetLb > 0 else { return .underWay }
        let reading = GoalCompletion.evaluate(
            targetLb: targetLb, history: history, now: now, calendar: calendar)
        // `basisLb` is nil exactly when `GoalCompletion` could not find
        // `minimumWeighInDays` of weigh-in days, even widened. A state
        // this consequential is not reached by guessing — with nothing
        // to average, the goal is simply still under way.
        guard let basis = reading.basisLb else { return .underWay }
        if reading.isMet { return .reached(reading) }
        // isMet is false with a non-nil basis only when the basis is
        // ABOVE the target (the weigh-in-day count is already satisfied
        // by basisLb being non-nil), so this is positive.
        let remaining = basis - targetLb
        return remaining < bandLb
            ? .approaching(basisLb: basis, remainingLb: remaining)
            : .underWay
    }
}

/// Whether editing a target by hand extends the journey already under
/// way, or starts a new one.
///
/// `GoalUpsert.save` re-stamps the journey start on any target change.
/// That is right for a reset and wrong for the commonest edit there is:
/// reaching 210 and deciding on 200. The re-stamp moved the start to
/// today's raw weigh-in and re-zeroed a bar that read 8.9 of 8.7 lb —
/// and the one path that preserved the journey, `StartChange.keep`, was
/// reachable only from the celebration, which does not fire until the
/// sustained basis has crossed (2026-08-14).
///
/// A target moved DOWN is the same journey with a further destination.
/// A target moved UP is a reset, and re-stamping is correct.
public enum JourneyContinuity {
    public static func continuesJourney(
        oldTargetLb: Double, newTargetLb: Double, progressLb: Double
    ) -> Bool {
        oldTargetLb > 0
            && newTargetLb < oldTargetLb
            && progressLb >= GoalProgress.minimumJourneyLb
    }
}
