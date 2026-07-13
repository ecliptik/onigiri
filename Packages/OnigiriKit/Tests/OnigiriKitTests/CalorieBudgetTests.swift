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

    @Test func projection() {
        // Losing 0.25 lb/day with 10 lb to go → 40 days
        #expect(CalorieBudget.projectedDaysToGoal(
            currentWeightLb: 190, targetWeightLb: 180, observedLossPerDayLb: 0.25
        ) == 40)
        // Flat trend → no projection
        #expect(CalorieBudget.projectedDaysToGoal(
            currentWeightLb: 190, targetWeightLb: 180, observedLossPerDayLb: 0
        ) == nil)
        // Already there
        #expect(CalorieBudget.projectedDaysToGoal(
            currentWeightLb: 179, targetWeightLb: 180, observedLossPerDayLb: 0.1
        ) == 0)
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
}
