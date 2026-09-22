import Foundation
import Testing
@testable import OnigiriKit

/// A finished day is judged by what happened on it. These pin the
/// arithmetic behind a real field report (2026-07-30), in synthetic
/// numbers: the Today screen showed "kcal left" and "100% — earned" for
/// days the calendar,
/// badges, and streak all counted as missed.
struct CompletedDayPlanTests {
    /// The reported shape. Burn 2,400, eaten 2,450 — a small SURPLUS.
    /// The old path forecast burn from the trailing average (2,700) and
    /// reported room left on a day that ended over break-even.
    @Test func aFinishedDayDoesNotQuoteABurnThatNeverHappened() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_400, requiredDailyDeficit: 200)
        #expect(plan.dailyBudget == 2_200)
        // What the headline subtracts from: over, not "50 left".
        #expect(plan.dailyBudget - 2_450 == -250)

        let forecast = CalorieBudget.projectedDailyBurn(averageKcal: 2_700)
        #expect(forecast == 2_700)          // the average that misled
        #expect(forecast - 200 - 2_450 == 50)  // the "kcal left" shown
    }

    /// The other reported day: the same deficit clears today's target and
    /// misses the one recorded that day. Whichever is right, the screens
    /// must not disagree — so the plan takes the target it's handed.
    @Test func theTargetItIsGivenIsTheTargetItUses() {
        let today = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: 200)
        let snapshot = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: 600)
        let intake = 1_600.0
        #expect(today.dailyBudget - intake > 0)      // "met" against 200
        #expect(snapshot.dailyBudget - intake < 0)   // missed against 600
        #expect(snapshot.requiredDailyDeficit == 600)
    }

    @Test func maintenanceSpendsTheWholeDayBurn() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_400, requiredDailyDeficit: 0)
        #expect(plan.dailyBudget == 2_400)
        #expect(plan.requiredDailyDeficit == 0)
    }

    @Test func aNegativeTargetCannotInflateTheBudget() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: -500)
        #expect(plan.dailyBudget == 2_000)
        #expect(plan.requiredDailyDeficit == 0)
    }

    /// A budget is what there is left to EAT, so it stops at nothing.
    ///
    /// The shape that shipped, in synthetic numbers: a target moved 10 lb
    /// lower kept a target date 14 days out, which asks 2,500 kcal/day of
    /// a 2,000 kcal burn. Unfloored the budget came to −500, and Today
    /// rendered "+500 kcal over" at 9am against an empty log — the app telling
    /// someone they had overeaten before their first meal (the user,
    /// 2026-08-18). The guardrails that would have caught it live in
    /// `plan()`, the Goal-tab preview; this is the function every real
    /// day is judged by and it had none.
    @Test func anImpossibleGoalCannotMakeTheBudgetNegative() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: 2_500)
        #expect(plan.dailyBudget == 0)
        // The ASK is not clamped with it — the goal really does want
        // that much, and the pace warning and the Goal screen both
        // need to be able to say so.
        #expect(plan.requiredDailyDeficit == 2_500)
    }

    /// How a caller tells "no budget existed" from "the budget is spent"
    /// — the pair `DailyGoalCard.hasNoBudget` reads, since `isAggressive`
    /// deliberately stays false here (see below).
    @Test func anOutrunBurnIsDistinguishableFromASpentBudget() {
        let impossible = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_900, requiredDailyDeficit: 2_500)
        #expect(impossible.requiredDailyDeficit > 0 && impossible.dailyBudget == 0)
        // Exactly break-even: the goal is met by eating nothing, which
        // is punishing but not impossible, so it reads the same way.
        let exact = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: 2_000)
        #expect(exact.dailyBudget == 0)
        // A real budget, merely tight, must NOT trip the same test.
        let tight = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_000, requiredDailyDeficit: 1_900)
        #expect(tight.dailyBudget == 100)
    }

    /// A past day is never "aggressive" — that flag asks the user to move
    /// their target date, which is meaningless for a day already spent.
    /// It stays false even when the budget floor bit, which is why the
    /// test above reads the two numbers rather than this flag.
    @Test func aPastDayIsNeverFlaggedAggressive() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_200, requiredDailyDeficit: 1_500)
        #expect(!plan.isAggressive)
    }

    /// The rule REVERSED on 2026-08-02: unworn hours cost you the active
    /// energy you didn't earn, because earning it is the whole reason to
    /// wear the watch. What they must NOT cost is the baseline — resting
    /// is floored by the body-metric estimate, so a day in the drawer
    /// keeps its ~1,900 kcal of just-being-alive.
    @Test func unwornHoursCostActivityButNeverTheBaseline() {
        let intake = 1_600.0, target = 600.0, estimatedResting = 1_900.0
        // Health recorded a partial day: resting short, some activity.
        let burn = DayBudget.dayBurn(
            activeKcal: 400, restingKcal: 1_500,
            estimatedRestingKcal: estimatedResting, burnCorrectionKcal: 0)
        // The baseline is restored, so the day isn't judged on 1,500.
        #expect(burn == 400 + estimatedResting)
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: burn, requiredDailyDeficit: target)
        #expect(DayBudget.met(intakeKcal: intake, budgetKcal: plan.dailyBudget))

        // The same day with the watch never on: the 400 is simply gone,
        // and that is allowed to flip the verdict.
        let noWatch = DayBudget.dayBurn(
            activeKcal: 0, restingKcal: 1_500,
            estimatedRestingKcal: estimatedResting, burnCorrectionKcal: 0)
        #expect(noWatch == estimatedResting)
        let stricter = CalorieBudget.completedDayPlan(
            dayBurnKcal: noWatch, requiredDailyDeficit: target)
        #expect(!DayBudget.met(intakeKcal: intake, budgetKcal: stricter.dailyBudget))
    }
}
