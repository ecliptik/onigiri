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

    // MARK: - expectedDailyBurn (the 2.1.4 clamp, shared by every surface)

    @Test func expectedBurnColdStartsAt2000() {
        #expect(CalorieBudget.expectedDailyBurn(averageKcal: nil) == 2000)
        #expect(CalorieBudget.expectedDailyBurn(averageKcal: 1500) == 2000)
    }

    @Test func expectedBurnUsesTheAverageWithRoomLeftInTheDay() {
        #expect(CalorieBudget.expectedDailyBurn(averageKcal: 2800, todayActualKcal: 1900) == 2800)
    }

    @Test func expectedBurnFollowsTodayOnceItTopsTheAverage() {
        // The fix behind "phone reads 150 left, widget reads 0 over" on
        // active days: today's actual burn outranks the average.
        #expect(CalorieBudget.expectedDailyBurn(averageKcal: 2800, todayActualKcal: 3100) == 3100)
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

    @Test func derivedPlanBudgetFollowsTodaysBurn() throws {
        // Same goal on a high-burn day: the deficit holds, the budget
        // rises with the clamped burn — Goal's preview used to miss this.
        let target = Self.cal.date(byAdding: .day, value: 100, to: Self.now)!
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: 200, targetWeightLb: 190, targetDate: target,
            averageDailyBurnKcal: 2800, todayActualBurnKcal: 3100,
            calendar: Self.cal, now: Self.now
        ))
        #expect(abs(plan.requiredDailyDeficit - 350) < 0.01)
        #expect(abs(plan.dailyBudget - 2750) < 0.01)
    }

    @Test func derivedMaintenancePlanEatsTheClampedBurn() throws {
        let plan = try #require(CalorieBudget.derivePlan(
            isMaintenance: true,
            averageDailyBurnKcal: 2800, todayActualBurnKcal: 3100
        ))
        #expect(plan.requiredDailyDeficit == 0)
        #expect(plan.dailyBudget == 3100)
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
