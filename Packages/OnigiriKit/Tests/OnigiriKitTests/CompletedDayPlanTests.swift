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

        let forecast = CalorieBudget.expectedDailyBurn(
            averageKcal: 2_722, todayActualKcal: 2_447)
        #expect(forecast == 2_722)          // the max() that misled
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

    /// A past day is never "aggressive" — that flag asks the user to move
    /// their target date, which is meaningless for a day already spent.
    @Test func aPastDayIsNeverFlaggedAggressive() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 1_200, requiredDailyDeficit: 1_500)
        #expect(!plan.isAggressive)
    }

    /// A watch taken off early must not read as a failed day. The plan's
    /// expected burn covers the unworn hours — no estimating required,
    /// because a snapshot is a recorded fact rather than a guess.
    @Test func unwornHoursDoNotManufactureAMissedDay() {
        let intake = 1_619.0, target = 621.0
        let measuredOnly = 1_562.0 + 397          // what Health recorded
        let effective = DayBudget.effectiveBurn(
            measuredKcal: measuredOnly, expectedKcal: 2_722, credit: .earned)

        #expect(measuredOnly - intake < target)   // judged short on wear time
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: effective, requiredDailyDeficit: target)
        #expect(DayBudget.met(intakeKcal: intake, budgetKcal: plan.dailyBudget))
    }
}
