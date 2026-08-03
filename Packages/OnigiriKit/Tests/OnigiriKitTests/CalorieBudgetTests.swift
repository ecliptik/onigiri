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
        #expect(over.caption == "kcal over budget")
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
