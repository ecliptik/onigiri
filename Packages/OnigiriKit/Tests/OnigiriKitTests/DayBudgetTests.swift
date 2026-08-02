import Foundation
import Testing
@testable import OnigiriKit

/// The day's budget, and the equivalence the whole model rests on.
struct DayBudgetTests {
    /// The point of the rewrite: "did I stay inside my budget" and "did I
    /// bank the deficit" are the SAME question, as long as both measure
    /// against the same burn. Asking them of two different burn figures is
    /// what let one screen say earned and another say missed.
    @Test func stayingInBudgetIsExactlyBankingTheDeficit() {
        let burn = 2_700.0, target = 500.0
        let budget = DayBudget.budget(dayBurnKcal: burn, requiredDeficitKcal: target)
        #expect(budget == 2_200)
        for intake in [1_700.0, 2_199.0, 2_200.0, 2_201.0, 2_600.0] {
            let inBudget = DayBudget.met(intakeKcal: intake, budgetKcal: budget)
            let bankedDeficit = (burn - intake) >= target
            #expect(inBudget == bankedDeficit)
        }
    }

    // MARK: Resting up front, active earned

    /// Resting is credited for the WHOLE day from midnight — the estimate
    /// floors it — so the morning doesn't read as a near-zero budget.
    @Test func restingIsCreditedUpFront() {
        // 8am: only 610 of the day's ~1,831 resting has accrued.
        #expect(DayBudget.dayBurn(
            activeKcal: 50, restingKcal: 610, estimatedRestingKcal: 1_831) == 1_881)
        // Same day at bedtime: measured has caught up, answer is stable
        // in the only way that matters — active is what moved it.
        #expect(DayBudget.dayBurn(
            activeKcal: 327, restingKcal: 1_831, estimatedRestingKcal: 1_831) == 2_158)
    }

    /// A real resting measurement above the estimate wins — the estimate
    /// is a floor, not a cap.
    @Test func measuredRestingAboveTheEstimateWins() {
        #expect(DayBudget.dayBurn(
            activeKcal: 0, restingKcal: 2_000, estimatedRestingKcal: 1_831) == 2_000)
    }

    /// No body metrics, no estimate: measured resting stands alone rather
    /// than the day losing its baseline.
    @Test func withoutBodyMetricsMeasuredRestingStandsAlone() {
        #expect(DayBudget.dayBurn(
            activeKcal: 300, restingKcal: 1_500, estimatedRestingKcal: nil) == 1_800)
    }

    /// The incentive, and the deliberate reversal of the old rule: active
    /// energy is EARNED. No watch, no active credit, smaller budget —
    /// where `effectiveBurn` used to backfill it from the plan so taking
    /// the watch off cost nothing (2026-08-02, the user).
    @Test func activeEnergyIsEarnedNotBackfilled() {
        let worn = DayBudget.dayBurn(
            activeKcal: 327, restingKcal: 1_831, estimatedRestingKcal: 1_831)
        let watchInADrawer = DayBudget.dayBurn(
            activeKcal: 0, restingKcal: 1_831, estimatedRestingKcal: 1_831)
        #expect(worn - watchInADrawer == 327)
        // Resting still survives the drawer — only activity is at stake.
        #expect(watchInADrawer == 1_831)
    }

    // MARK: Guards

    @Test func aNegativeTargetCannotInflateTheBudget() {
        #expect(DayBudget.budget(dayBurnKcal: 2_400, requiredDeficitKcal: -300) == 2_400)
    }

    @Test func eatingExactlyTheBudgetCounts() {
        #expect(DayBudget.met(intakeKcal: 2_200, budgetKcal: 2_200))
        #expect(!DayBudget.met(intakeKcal: 2_200.5, budgetKcal: 2_200))
    }

    // MARK: Settings resolve to today's behavior when unset

    @Test func defaultsMatchThePreviousBehavior() {
        #expect(BudgetStyle.resolve(nil) == .automatic)
        #expect(BudgetStyle.resolve("nonsense") == .automatic)
        #expect(BudgetStyle.resolve("fixed") == .fixed)
        // Each option explains itself under the picker.
        #expect(!BudgetStyle.automatic.explanation.isEmpty)
        #expect(!BudgetStyle.fixed.explanation.isEmpty)
        #expect(BudgetStyle.automatic.creditsActivity)
        #expect(!BudgetStyle.fixed.creditsActivity)
    }

    // MARK: Headline wording

    /// "Over" meant two different things and told them as one: the
    /// reported day banked a 445 kcal deficit and still said "246 kcal
    /// over", which reads as a gain.
    @Test func pastTheBudgetButUnderYourBurnReadsAsShortNotOver() {
        let short = CalorieBudget.remainingHeadline(-246, deficitKcal: 445)
        #expect(short.value == 246)
        #expect(short.caption == "kcal short")

        // Ate more than burned — genuinely over.
        let over = CalorieBudget.remainingHeadline(-208, deficitKcal: -27)
        #expect(over.caption == "kcal over")

        // Room left is unchanged either way.
        #expect(CalorieBudget.remainingHeadline(300, deficitKcal: 800).caption == "kcal left")
        #expect(CalorieBudget.remainingHeadline(300, deficitKcal: -50).caption == "kcal left")
    }

    /// Exactly break-even is not a deficit, so it can't be "short".
    @Test func breakEvenReadsAsOver() {
        #expect(CalorieBudget.remainingHeadline(-100, deficitKcal: 0).caption == "kcal over")
    }
}
