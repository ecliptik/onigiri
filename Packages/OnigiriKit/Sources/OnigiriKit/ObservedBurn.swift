import Foundation

/// What the SCALE says you burn, as opposed to what the watch measured.
///
/// The Goal screen's "Last 30 days" row has always shown a predicted
/// weight change beside the actual one, and they rarely agree. The row
/// stated the disagreement and left it there — "shouldn't we get better
/// at this?" (the user, 2026-08-18). This is the one number that makes
/// the gap legible, and it needs nothing new from Health:
///
///     observedBurn = meanDailyIntake − scaleRateLbPerDay × 3500
///
/// Eating 2,000 kcal/day while the scale falls 2 lb in 30 days implies
/// ~2,233 kcal/day of real expenditure, whatever the watch recorded.
///
/// **It REPORTS; it does not judge, and nothing plans from it.** That
/// separation is the same one the budget and the weight basis already
/// draw, and here it is load-bearing for a specific reason: this figure
/// cannot tell you WHY the model missed. At least five causes push it,
/// and it sees one number:
///
/// 1. Intake under-logging — routinely 20–30% in the literature.
/// 2. A resting estimate off for this body (`BasalEstimate` carries a
///    midpoint constant where sex is unspecified).
/// 3. Health's active energy running high or low for these activities.
/// 4. Water, glycogen and sodium, which 30 days damps but never clears.
/// 5. The 3,500 kcal/lb constant, an approximation of a
///    composition-dependent quantity.
///
/// Causes 1–3 would justify moving a budget. Cause 4 would not, and a
/// correction that fires on water weight chases its own tail. So this
/// stays a reading on a disclosure row. Feeding it back into `dayBurn`
/// automatically would re-create the trailing-average substitution that
/// `PLAN-earned-budget` DELETED rather than kept — "active is earned:
/// raw measured, never filled, never estimated" — and it would do it
/// silently, which is worse than the version that was removed. If a
/// correction is ever wanted it must be OFFERED and stored, the shape
/// the finish-line date button takes.
public enum ObservedBurn {
    /// Fewest tracked days in the window before the figure means
    /// anything.
    ///
    /// The mean intake of the tracked days stands in for every day in
    /// the window — the scale moved across all of them, including the
    /// ones with nothing logged. That substitution is only honest when
    /// the untracked remainder is small. Below this it is not a noisy
    /// estimate, it is a different quantity: a fortnight of logging
    /// against a month of eating.
    public static let minimumTrackedDays = 21

    /// nil when the window is too thin to speak, which is a state the
    /// caller must render as SILENCE rather than as a zero.
    ///
    /// - Parameters:
    ///   - meanDailyIntakeKcal: mean over the TRACKED days — the same
    ///     gate `GoalTrendStats` applies to `predicted30Lb`, and for the
    ///     same reason: a day with burn and no logged food reads as a
    ///     ~2,500 kcal deficit, and that fiction would land here as a
    ///     wildly overstated burn.
    ///   - scaleRateLbPerDay: `WeightTrend.Change.actualRateLbPerDay`,
    ///     negative while losing. A RATE, so a month weighed twice and a
    ///     month weighed daily are read the same way.
    public static func kcalPerDay(
        meanDailyIntakeKcal: Double,
        scaleRateLbPerDay: Double,
        trackedDays: Int,
        minimumTrackedDays: Int = minimumTrackedDays
    ) -> Double? {
        guard trackedDays >= minimumTrackedDays else { return nil }
        // Losing weight (a negative rate) means burning MORE than was
        // eaten, so the subtraction adds.
        return meanDailyIntakeKcal - scaleRateLbPerDay * WeightTrend.Change.kcalPerLb
    }
}
