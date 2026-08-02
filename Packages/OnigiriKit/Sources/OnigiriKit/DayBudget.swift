import Foundation

/// The day's eating budget — ONE number, from the day's own burn.
///
/// This replaces judging a day by its measured deficit. The two are the
/// same question asked differently, and asking it two ways is what broke:
/// the budget forecast burn from the trailing average while the verdict
/// used what the watch happened to record, so a screen could show room
/// left on a day another screen called a miss (2026-07-30), and Details
/// could show "695 kcal left" two rows above "197 kcal surplus"
/// (2026-08-02).
///
///     budget = dayBurn − requiredDeficit
///     met    = intake ≤ budget
///
/// which is algebraically the deficit rule — `dayBurn − intake ≥
/// requiredDeficit` — provided BOTH use `dayBurn`. That is the whole
/// fix: one burn figure, everywhere, for a given day.
///
/// The burn is the day's OWN — resting credited up front, active earned
/// by moving (2026-08-02, the user). The trailing-average expectation
/// this used to fall back on is gone: it promised calories the day never
/// went on to earn, so a below-average day quoted an above-average
/// allowance right up to bedtime.
public enum DayBudget {
    /// The burn a day is judged against, from that day's own two
    /// channels. HealthKit's split maps onto the model exactly:
    /// `basalEnergyBurned` is the baseline, and `activeEnergyBurned` is
    /// DEFINED as energy above resting, so adding them double-counts
    /// nothing.
    ///
    /// **Resting is credited up front** — the whole day's worth, from
    /// midnight. It's the predictable part and happens whether or not
    /// you move, so `max` against the estimate covers all three cases in
    /// one expression: today before it has accrued (the estimate wins),
    /// a finished day (they agree), a day the phone/watch was off (the
    /// estimate floors it, so resting never reads as zero).
    ///
    /// **Active is earned** — raw measured, never filled, never
    /// estimated. No watch, no active credit, smaller budget. That is
    /// the incentive, and it's why the old expected-burn substitution
    /// had to go: its entire job was protecting unworn days, which is
    /// precisely what we now decline to do.
    ///
    /// `estimatedRestingKcal` is `BasalEstimate.restingKcal` from Health's
    /// body metrics; nil when the body isn't described well enough, in
    /// which case measured resting stands alone.
    public static func dayBurn(
        activeKcal: Double,
        restingKcal: Double,
        estimatedRestingKcal: Double?
    ) -> Double {
        activeKcal + max(restingKcal, estimatedRestingKcal ?? 0)
    }

    /// Calories available to eat. Can go negative on a punishing target;
    /// callers show that as "over", never as a negative allowance.
    public static func budget(dayBurnKcal: Double, requiredDeficitKcal: Double) -> Double {
        dayBurnKcal - max(0, requiredDeficitKcal)
    }

    /// Did the day land inside its budget? The single verdict every
    /// surface asks — Today's card, the calendar, the badge, the streak.
    public static func met(intakeKcal: Double, budgetKcal: Double) -> Bool {
        intakeKcal <= budgetKcal
    }

    /// The day's net, positive for a deficit. Deliberately NOT
    /// `DailyEnergySummary.balanceKcal`, which subtracts raw measured
    /// burn: the budget above it already holds the whole day's resting,
    /// so at 9am the raw figure calls a breakfast a surplus while the
    /// ring in the same screen says there's room left. Same day, same
    /// question, two answers — the pairing this whole model exists to
    /// end. Verdict-shaped numbers come through here; the Burned flank
    /// and the Active/Resting rows stay on Health's raw totals, because
    /// those report a measurement rather than reach a judgment.
    public static func deficit(intakeKcal: Double, dayBurnKcal: Double) -> Double {
        dayBurnKcal - intakeKcal
    }
}
