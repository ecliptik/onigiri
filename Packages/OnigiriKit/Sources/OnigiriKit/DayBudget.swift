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

    /// The active half of a day burn that has been floored or ratcheted
    /// since it was composed — `dayBurn` less the resting actually
    /// credited.
    ///
    /// Details is a card that has to ADD UP: the resting row already
    /// prints what the budget was built on rather than what Health has
    /// recorded so far (2026-08-02), and active was still printing the
    /// raw measurement, so Active + Resting fell short of the burn the
    /// budget and Net were cut from — 499 + 1,931 under a 2,444 the
    /// screen never showed (the user, 2026-08-24). `TodayBurnFloor`
    /// ratchets the TOTAL, so the difference belongs to no channel by
    /// construction; it is credited to active because that is the
    /// channel Health revises — the phone's step-derived estimate and
    /// the watch's measurement reconciling against each other — and
    /// because resting has its own floor and its own explanation one row
    /// below.
    ///
    /// Never less than what was measured: a stale or zero `dayBurnKcal`
    /// (before the first refresh lands) must not print an active figure
    /// below the one Health is reporting.
    /// How far a credited figure must sit above Health's own reading
    /// before the row prints BOTH. The credit is the number the budget
    /// was cut from and it always shows; the measurement underneath is
    /// only there to explain a disagreement with the Health app, and a
    /// difference nobody would notice is not a disagreement worth a
    /// second line (the user, 2026-08-24: "we're talking 10s of calories
    /// here and consistency and simplicity is important").
    ///
    /// ONE threshold for both rows, because the reader cannot tell which
    /// floor produced which gap and shouldn't have to. It bites only on
    /// active: resting's morning gap is the whole un-accrued part of the
    /// day's estimate — hundreds of kcal — and clears any threshold this
    /// side of useless.
    public static let creditNoteThresholdKcal = 50.0

    public static func creditedActive(
        dayBurnKcal: Double,
        creditedRestingKcal: Double,
        measuredActiveKcal: Double
    ) -> Double {
        max(measuredActiveKcal, dayBurnKcal - creditedRestingKcal)
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
    /// end. Verdict-shaped numbers come through here, and so do the
    /// Active/Resting rows that have to add up to them
    /// (`creditedActive`): a card printing raw halves under a verdict
    /// cut from a floored, ratcheted total cannot be added up by hand.
    /// Health's own measurement keeps its place UNDER each of those
    /// rows, where it explains the credit rather than contradicting it.
    public static func deficit(intakeKcal: Double, dayBurnKcal: Double) -> Double {
        dayBurnKcal - intakeKcal
    }
}
