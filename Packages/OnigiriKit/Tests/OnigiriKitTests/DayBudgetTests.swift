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
        let budget = DayBudget.budget(effectiveBurnKcal: burn, requiredDeficitKcal: target)
        #expect(budget == 2_200)
        for intake in [1_700.0, 2_199.0, 2_200.0, 2_201.0, 2_600.0] {
            let inBudget = DayBudget.met(intakeKcal: intake, budgetKcal: budget)
            let bankedDeficit = (burn - intake) >= target
            #expect(inBudget == bankedDeficit)
        }
    }

    // MARK: Earn extra (the default)

    @Test func measuredBurnRaisesTheBudgetButNeverLowersIt() {
        // Burned more than planned: the extra is yours to eat.
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 2_900, expectedKcal: 2_500, credit: .earned) == 2_900)
        // Watch off at 6pm, only 1,900 recorded — costs nothing.
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 1_900, expectedKcal: 2_500, credit: .earned) == 2_500)
    }

    /// The reported day: 2,000 budget, 1,700 eaten, watch off — still 300
    /// left, and still a met day. Nothing about the watch changes it.
    @Test func takingTheWatchOffChangesNothing() {
        let expected = 2_500.0, target = 500.0, intake = 1_700.0
        let wornAllDay = DayBudget.budget(
            effectiveBurnKcal: DayBudget.effectiveBurn(
                measuredKcal: 2_500, expectedKcal: expected, credit: .earned),
            requiredDeficitKcal: target)
        let offAtSix = DayBudget.budget(
            effectiveBurnKcal: DayBudget.effectiveBurn(
                measuredKcal: 1_450, expectedKcal: expected, credit: .earned),
            requiredDeficitKcal: target)
        #expect(wornAllDay == offAtSix)
        #expect(wornAllDay - intake == 300)
        #expect(DayBudget.met(intakeKcal: intake, budgetKcal: offAtSix))
    }

    // MARK: Fixed

    @Test func fixedIgnoresMeasuredBurnInBothDirections() {
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 2_900, expectedKcal: 2_500, credit: .fixed) == 2_500)
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 1_400, expectedKcal: 2_500, credit: .fixed) == 2_500)
    }

    /// Even on Fixed, a day with no snapshot has to fall back to what was
    /// measured — otherwise it would have no burn at all and read as a
    /// catastrophic overage.
    @Test func withoutASnapshotBothStylesUseWhatWasMeasured() {
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 2_100, expectedKcal: nil, credit: .fixed) == 2_100)
        #expect(DayBudget.effectiveBurn(
            measuredKcal: 2_100, expectedKcal: nil, credit: .earned) == 2_100)
    }

    // MARK: Guards

    @Test func aNegativeTargetCannotInflateTheBudget() {
        #expect(DayBudget.budget(effectiveBurnKcal: 2_400, requiredDeficitKcal: -300) == 2_400)
    }

    @Test func eatingExactlyTheBudgetCounts() {
        #expect(DayBudget.met(intakeKcal: 2_200, budgetKcal: 2_200))
        #expect(!DayBudget.met(intakeKcal: 2_200.5, budgetKcal: 2_200))
    }

    // MARK: Settings resolve to today's behavior when unset

    @Test func defaultsMatchThePreviousBehavior() {
        #expect(ActivityCredit.resolve(nil) == .earned)
        #expect(ActivityCredit.resolve("nonsense") == .earned)
        #expect(ExpectedBurnSource.resolve(nil) == .automatic)
        #expect(ExpectedBurnSource.resolve("nonsense") == .automatic)
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
