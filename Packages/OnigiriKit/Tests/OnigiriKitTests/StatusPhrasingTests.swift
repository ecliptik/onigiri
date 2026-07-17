import Testing
import Foundation
@testable import OnigiriKit

/// The ask-back intent's pure half: numbers in, spoken sentence +
/// snippet strings out. The intent itself is HealthKit-bound; this is
/// where the grammar and the over/under boundaries are pinned.
struct StatusPhrasingTests {
    private func state(
        intake: Double = 0, activeBurn: Double = 0, restingBurn: Double = 0,
        sodiumMg: Double = 0, waterOz: Double = 0, budget: Double? = nil
    ) -> DailyPlanLoader.State {
        DailyPlanLoader.State(
            summary: DailyEnergySummary(
                intakeKcal: intake, activeBurnKcal: activeBurn,
                restingBurnKcal: restingBurn, sodiumMg: sodiumMg, waterOz: waterOz),
            deficitTargetKcal: nil,
            gaugeProgress: 0,
            dailyBudgetKcal: budget
        )
    }

    @Test func caloriesLeftUnderBudget() {
        let status = StatusPhrasing.phrase(
            metric: .caloriesLeft, plan: state(intake: 2_300, budget: 2_450),
            waterGoalOz: 64, sodiumLimitMg: 2_300)
        #expect(status.headline == "150")
        #expect(status.caption == "kcal left")
        #expect(status.spoken == "You have 150 calories left today.")
    }

    @Test func caloriesOverBudgetSpeaksTheOverage() {
        let status = StatusPhrasing.phrase(
            metric: .caloriesLeft, plan: state(intake: 2_600, budget: 2_450),
            waterGoalOz: 64, sodiumLimitMg: 2_300)
        #expect(status.headline == "150")
        #expect(status.caption == "kcal over")
        #expect(status.spoken == "You're 150 calories over budget today.")
    }

    @Test func caloriesWithoutAGoalReportsTheBalance() {
        let status = StatusPhrasing.phrase(
            metric: .caloriesLeft,
            plan: state(intake: 1_540, activeBurn: 600, restingBurn: 1_410),
            waterGoalOz: 64, sodiumLimitMg: 2_300)
        #expect(status.caption == "kcal eaten")
        #expect(status.spoken.contains("1,540 calories"))
        #expect(status.spoken.contains("2,010"))
        #expect(status.spoken.contains("Set a goal"))
    }

    @Test func waterBehindAndAtGoal() {
        let behind = StatusPhrasing.phrase(
            metric: .water, plan: state(waterOz: 24),
            waterGoalOz: 72, sodiumLimitMg: 2_300)
        #expect(behind.headline == "24 / 72 oz")
        #expect(behind.spoken == "You're at 24 of 72 ounces of water today.")

        let met = StatusPhrasing.phrase(
            metric: .water, plan: state(waterOz: 80),
            waterGoalOz: 72, sodiumLimitMg: 2_300)
        #expect(met.spoken == "Water goal met — 80 of 72 ounces today.")
    }

    @Test func nutrientWithSlotLimitSpeaksTheJudgment() {
        let over = StatusPhrasing.nutrientStatus(
            nutrient: .saturatedFat, value: 25, target: 20, mode: .limit)
        #expect(over.headline == "25 / 20 g")
        #expect(over.caption == "saturated fat — over limit")
        #expect(over.spoken == "You're over your saturated fat limit — 25 of 20 grams today.")

        let under = StatusPhrasing.nutrientStatus(
            nutrient: .sugar, value: 18, target: 36, mode: .limit)
        #expect(under.spoken == "You're at 18 of 36 grams of sugar today.")
    }

    @Test func nutrientWithSlotGoalCelebratesWhenMet() {
        let met = StatusPhrasing.nutrientStatus(
            nutrient: .protein, value: 130, target: 120, mode: .goal)
        #expect(met.spoken == "Protein goal met — 130 of 120 grams today.")

        let behind = StatusPhrasing.nutrientStatus(
            nutrient: .protein, value: 32, target: 120, mode: .goal)
        #expect(behind.headline == "32 / 120 g")
        #expect(behind.spoken == "You're at 32 of 120 grams of protein today.")
    }

    @Test func untrackedNutrientReportsPlainTotal() {
        let plain = StatusPhrasing.nutrientStatus(
            nutrient: .caffeine, value: 240, target: nil, mode: nil)
        #expect(plain.headline == "240 mg")
        #expect(plain.caption == "caffeine")
        #expect(plain.spoken == "You've had 240 milligrams of caffeine today.")
    }

    @Test func sodiumUnderAndOverLimit() {
        let under = StatusPhrasing.phrase(
            metric: .sodium, plan: state(sodiumMg: 1_450),
            waterGoalOz: 64, sodiumLimitMg: 2_300)
        #expect(under.headline == "1,450 / 2,300 mg")
        #expect(under.caption == "sodium")
        #expect(under.spoken == "You're at 1,450 of 2,300 milligrams of sodium today.")

        let over = StatusPhrasing.phrase(
            metric: .sodium, plan: state(sodiumMg: 2_600),
            waterGoalOz: 64, sodiumLimitMg: 2_300)
        #expect(over.caption == "sodium — over limit")
        #expect(over.spoken == "You're over your sodium limit — 2,600 of 2,300 milligrams today.")
    }
}
