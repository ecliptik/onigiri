import Foundation
import Testing
@testable import OnigiriKit

struct CalorieBudgetTests {
    @Test func twentyPoundsOverFourMonths() {
        // 20 lb * 3500 kcal / 120 days ≈ 583 kcal/day deficit
        let plan = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 180,
            daysRemaining: 120, averageDailyBurn: 2600
        )
        #expect(abs(plan.requiredDailyDeficit - 583.33) < 0.01)
        #expect(abs(plan.dailyBudget - 2016.67) < 0.01)
        #expect(!plan.isAggressive)
    }

    @Test func crashDietIsFlaggedAggressive() {
        // 20 lb in 30 days needs a 2333 kcal/day deficit
        let plan = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 180,
            daysRemaining: 30, averageDailyBurn: 2600
        )
        #expect(plan.isAggressive)
    }

    @Test func lowBudgetIsFlaggedAggressive() {
        let plan = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 180,
            daysRemaining: 120, averageDailyBurn: 2000
        )
        #expect(plan.dailyBudget < CalorieBudget.minReasonableBudget)
        #expect(plan.isAggressive)
    }

    /// The gap the flat 1,500 could not see: a budget above it and below
    /// the body's own resting energy.
    ///
    /// Deliberately a REACHABLE plan, not a pathological one — 10 lb in
    /// 44 days is an 800 kcal/day deficit, which against a 2,400 kcal
    /// average burn leaves 1,600 to eat. That clears `minReasonableBudget`
    /// by 100 and sits 142 UNDER the ~1,742 resting estimate for the
    /// body the seeder describes (178 cm, 40 years, 200 lb).
    @Test func aBudgetUnderTheBodysRestingEnergyIsAggressive() {
        let restingKcal = BasalEstimate.restingKcal(
            weightLb: 200, heightCm: 178, ageYears: 40, sex: .unspecified)
        #expect(abs((restingKcal ?? 0) - 1741.7) < 0.5)

        let inputs = (currentWeightLb: 200.0, targetWeightLb: 190.0,
                      daysRemaining: 44, averageDailyBurn: 2400.0)
        let unguarded = CalorieBudget.plan(
            currentWeightLb: inputs.currentWeightLb, targetWeightLb: inputs.targetWeightLb,
            daysRemaining: inputs.daysRemaining, averageDailyBurn: inputs.averageDailyBurn
        )
        // The budget that used to pass silently.
        #expect(abs(unguarded.dailyBudget - 1604.5) < 1)
        #expect(unguarded.dailyBudget > CalorieBudget.minReasonableBudget)
        #expect(unguarded.dailyBudget < (restingKcal ?? 0))
        #expect(!unguarded.isAggressive)

        let guarded = CalorieBudget.plan(
            currentWeightLb: inputs.currentWeightLb, targetWeightLb: inputs.targetWeightLb,
            daysRemaining: inputs.daysRemaining, averageDailyBurn: inputs.averageDailyBurn,
            restingFloorKcal: restingKcal
        )
        #expect(guarded.isAggressive)
        // Same plan, same numbers — only the verdict moved.
        #expect(guarded.dailyBudget == unguarded.dailyBudget)
        #expect(guarded.requiredDailyDeficit == unguarded.requiredDailyDeficit)
    }

    /// nil resting — Health can't describe the body — must reproduce the
    /// old behaviour exactly, or the guardrail vanishes with its input on
    /// every device that never granted the body reads.
    @Test func withoutARestingEstimateTheFlatFloorStillHolds() {
        let comfortable = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 190,
            daysRemaining: 44, averageDailyBurn: 2400, restingFloorKcal: nil
        )
        #expect(!comfortable.isAggressive)
        let tooLow = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 180,
            daysRemaining: 120, averageDailyBurn: 2000, restingFloorKcal: nil
        )
        #expect(tooLow.isAggressive)
    }

    /// The resting floor RAISES the bar and never lowers it: a body with
    /// a small resting figure must not talk the flat 1,500 down.
    @Test func aLowRestingEstimateNeverRelaxesTheFlatFloor() {
        let plan = CalorieBudget.plan(
            currentWeightLb: 200, targetWeightLb: 180,
            daysRemaining: 120, averageDailyBurn: 2000, restingFloorKcal: 1200
        )
        #expect(plan.dailyBudget < CalorieBudget.minReasonableBudget)
        #expect(plan.isAggressive)
    }

    /// A COMPLETED day is never aggressive, whatever the floor says —
    /// the property Today's card reads. It is why the card needs its own
    /// pace-warning input rather than `plan.isAggressive`, and why that
    /// warning was unreachable until 2026-08-16.
    @Test func aCompletedDayIsNeverTalkedOutOfWhatItWas() {
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: 2000, requiredDailyDeficit: 1200)
        #expect(plan.dailyBudget == 800)
        #expect(!plan.isAggressive)
    }

    @Test func maintenancePlanBudgetIsTheBurn() {
        let plan = CalorieBudget.maintenancePlan(averageDailyBurn: 2450)
        #expect(plan.requiredDailyDeficit == 0)
        #expect(plan.dailyBudget == 2450)
        #expect(!plan.isAggressive)
    }

    @Test func goalAlreadyMet() {
        let plan = CalorieBudget.plan(
            currentWeightLb: 180, targetWeightLb: 180,
            daysRemaining: 60, averageDailyBurn: 2600
        )
        #expect(plan.requiredDailyDeficit == 0)
        #expect(plan.dailyBudget == 2600)
    }

    @Test func remainingHeadlineFlipsToOverWithPositiveNumber() {
        let left = CalorieBudget.remainingHeadline(402)
        #expect(left.value == 402)
        #expect(left.caption == "kcal left")
        let over = CalorieBudget.remainingHeadline(-138)
        #expect(over.value == 138)
        #expect(over.caption == "kcal over")
        #expect(CalorieBudget.remainingHeadline(0).caption == "kcal left")
    }

    // MARK: - projectedDailyBurn (the Goal/onboarding preview basis)

    @Test func expectedBurnColdStartsAt2000() {
        #expect(CalorieBudget.projectedDailyBurn(averageKcal: nil) == 2000)
        #expect(CalorieBudget.projectedDailyBurn(averageKcal: 1500) == 2000)
    }

    @Test func projectedBurnIsTheAverageAndNothingElse() {
        // Today's own burn used to floor this so the Goal preview
        // couldn't read lower than Today. That made the figure neither
        // an average nor today — and it still left the two screens 726
        // kcal apart at lunchtime under one label (2026-08-02). Goal
        // now names both, so this one is free to mean what it says.
        #expect(CalorieBudget.projectedDailyBurn(averageKcal: 2800) == 2800)
    }

    // MARK: - derivePlan (one derivation for Today/Goal/onboarding/watch)

    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9))!

    @Test func derivedWeightPlanSpreadsPoundsOverDays() throws {
        // 10 lb * 3500 / 100 days = 350 kcal/day deficit off a 2800 burn.
        let target = Self.cal.date(byAdding: .day, value: 100, to: Self.now)!
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: 200, targetWeightLb: 190, targetDate: target,
            averageDailyBurnKcal: 2800,
            calendar: Self.cal, now: Self.now
        ))
        #expect(abs(plan.requiredDailyDeficit - 350) < 0.01)
        #expect(abs(plan.dailyBudget - 2450) < 0.01)
    }

    /// The preview is a PROJECTION and stays one: an active afternoon
    /// moves what Today allows, not what an average day allows. The
    /// deficit is the part that never depended on burn either way.
    @Test func derivedPlanIgnoresHowTodayIsGoing() throws {
        let target = Self.cal.date(byAdding: .day, value: 100, to: Self.now)!
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: 200, targetWeightLb: 190, targetDate: target,
            averageDailyBurnKcal: 2800,
            calendar: Self.cal, now: Self.now
        ))
        #expect(abs(plan.requiredDailyDeficit - 350) < 0.01)
        #expect(abs(plan.dailyBudget - 2450) < 0.01)
    }

    @Test func derivedMaintenancePlanEatsTheAverageBurn() throws {
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: true, averageDailyBurnKcal: 2800
        ))
        #expect(plan.requiredDailyDeficit == 0)
        #expect(plan.dailyBudget == 2800)
    }

    @Test func derivedMaintenancePlanColdStartsAt2000() throws {
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: true, averageDailyBurnKcal: nil
        ))
        #expect(plan.dailyBudget == 2000)
    }

    @Test func derivedWeightPlanNeedsAWeight() {
        let target = Self.cal.date(byAdding: .day, value: 100, to: Self.now)!
        #expect(CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: nil, targetWeightLb: 190, targetDate: target,
            averageDailyBurnKcal: 2800,
            calendar: Self.cal, now: Self.now
        ) == nil)
    }
}
