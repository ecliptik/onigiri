import Foundation
import Testing
@testable import OnigiriKit

/// A finished day is judged by what happened on it. These pin the
/// arithmetic behind a real field report (2026-07-30): the Today screen
/// showed "67 kcal left" and "100% — earned" for days the calendar,
/// badges, and streak all counted as missed.
struct CompletedDayPlanTests {
    /// The reported day. Burn 2,447, eaten 2,474 — a 27 kcal SURPLUS.
    /// The old path forecast burn from the trailing average (2,722) and
    /// reported room left on a day that ended over break-even.
    @Test func aFinishedDayDoesNotQuoteABurnThatNeverHappened() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2_447, requiredDailyDeficit: 181)
        #expect(plan.dailyBudget == 2_266)
        // What the headline subtracts from: over, not "67 left".
        #expect(plan.dailyBudget - 2_474 == -208)

        let forecast = CalorieBudget.projectedDailyBurn(averageKcal: 2_722)
        #expect(forecast == 2_722)          // the average that misled
        #expect(forecast - 181 - 2_474 == 67)  // the "67 kcal left" shown
    }

    /// The other reported day: the same deficit clears today's target and
    /// misses the one recorded that day. Whichever is right, the screens
    /// must not disagree — so the plan takes the target it's handed.
    @Test func theTargetItIsGivenIsTheTargetItUses() {
        let today = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_959, requiredDailyDeficit: 181)
        let snapshot = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_959, requiredDailyDeficit: 621)
        let intake = 1_619.0
        #expect(today.dailyBudget - intake > 0)      // "met" against 181
        #expect(snapshot.dailyBudget - intake < 0)   // missed against 621
        #expect(snapshot.requiredDailyDeficit == 621)
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
    /// The exact shape that shipped: a target moved 210 → 200 lb kept a
    /// target date 13 days out, which asks 2,453 kcal/day of a 1,956
    /// kcal burn. Unfloored the budget came to −497, and Today rendered
    /// "+498 kcal over" at 9am against an empty log — the app telling
    /// someone they had overeaten before their first meal (the user,
    /// 2026-08-18). The guardrails that would have caught it live in
    /// `plan()`, the Goal-tab preview; this is the function every real
    /// day is judged by and it had none.
    @Test func anImpossibleGoalCannotMakeTheBudgetNegative() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_956, requiredDailyDeficit: 2_453)
        #expect(plan.dailyBudget == 0)
        // The ASK is not clamped with it — the goal really does want
        // that much, and the pace warning and the Goal screen both
        // need to be able to say so.
        #expect(plan.requiredDailyDeficit == 2_453)
    }

    /// How a caller tells "no budget existed" from "the budget is spent"
    /// — the pair `DailyGoalCard.hasNoBudget` reads, since `isAggressive`
    /// deliberately stays false here (see below).
    @Test func anOutrunBurnIsDistinguishableFromASpentBudget() {
        let impossible = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_956, requiredDailyDeficit: 2_453)
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
        let intake = 1_619.0, target = 621.0, estimatedResting = 1_900.0
        // Health recorded a partial day: resting short, some activity.
        let burn = DayBudget.dayBurn(
            activeKcal: 397, restingKcal: 1_562,
            estimatedRestingKcal: estimatedResting)
        // The baseline is restored, so the day isn't judged on 1,562.
        #expect(burn == 397 + estimatedResting)
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: burn, requiredDailyDeficit: target)
        #expect(DayBudget.met(intakeKcal: intake, budgetKcal: plan.dailyBudget))

        // The same day with the watch never on: the 397 is simply gone,
        // and that is allowed to flip the verdict.
        let noWatch = DayBudget.dayBurn(
            activeKcal: 0, restingKcal: 1_562,
            estimatedRestingKcal: estimatedResting)
        #expect(noWatch == estimatedResting)
        let stricter = CalorieBudget.completedDayPlan(
            dayBurnKcal: noWatch, requiredDailyDeficit: target)
        #expect(!DayBudget.met(intakeKcal: intake, budgetKcal: stricter.dailyBudget))
    }
}
