import Foundation

/// The day's eating budget — ONE number, decided by the plan, that
/// measured burn can raise but never lower.
///
/// This replaces judging a day by its measured deficit. The two are the
/// same question asked differently, and asking it two ways is what broke:
/// the budget forecast burn from the trailing average while the verdict
/// used what the watch happened to record, so a screen could show room
/// left on a day another screen called a miss (2026-07-30).
///
///     budget = effectiveBurn − requiredDeficit
///     met    = intake ≤ budget
///
/// which is algebraically the old deficit rule — `effectiveBurn − intake
/// ≥ requiredDeficit` — provided BOTH use `effectiveBurn`. That is the
/// whole fix: one burn figure, everywhere, for a given day.
///
/// Taking the watch off cannot cost you anything, because measured burn
/// only ever raises the figure. That also makes estimating unworn hours
/// unnecessary: the plan's expected burn already covers them.
public enum DayBudget {
    /// The burn a day is judged against: the plan's expectation for that
    /// day, raised if the day actually burned more. Never lowered — an
    /// unworn watch is missing data, not a smaller day.
    ///
    /// `expectedKcal` is the value snapshotted when the day happened
    /// (`PlanBurnHistory`), so history is judged by the plan it was living
    /// under. Days with no snapshot fall back to the caller's current
    /// expectation, matching how a missing deficit target behaves.
    public static func effectiveBurn(
        measuredKcal: Double,
        expectedKcal: Double?,
        style: BudgetStyle = SharedStore.budgetStyle
    ) -> Double {
        // Fixed: the plan's number and nothing else — but a day with no
        // snapshot still has to fall back to what was measured, or it
        // would have no burn at all.
        if !style.creditsActivity, let expectedKcal { return expectedKcal }
        return max(measuredKcal, expectedKcal ?? 0)
    }

    /// Calories available to eat. Can go negative on a punishing target;
    /// callers show that as "over", never as a negative allowance.
    public static func budget(effectiveBurnKcal: Double, requiredDeficitKcal: Double) -> Double {
        effectiveBurnKcal - max(0, requiredDeficitKcal)
    }

    /// Did the day land inside its budget? The single verdict every
    /// surface asks — Today's card, the calendar, the badge, the streak.
    public static func met(intakeKcal: Double, budgetKcal: Double) -> Bool {
        intakeKcal <= budgetKcal
    }
}
