import Foundation
import Testing
@testable import OnigiriKit

/// Plan assembly for the watch/widget surfaces — every branch of
/// makeState, which carried the 2.1.4 clamp to complications with zero
/// coverage (the fetch layer is HealthKit-bound; the assembly isn't).
@MainActor
struct DailyPlanLoaderTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9))!

    private static func summary(intake: Double, burn: Double) -> DailyEnergySummary {
        DailyEnergySummary(
            intakeKcal: intake, activeBurnKcal: burn * 0.3,
            restingBurnKcal: burn * 0.7, sodiumMg: 0, waterOz: 0
        )
    }

    private static func weightGoal(fallbackLb: Double? = nil) -> SyncedGoal {
        SyncedGoal(
            targetWeightLb: 190,
            targetDate: cal.date(byAdding: .day, value: 100, to: now)!,
            fallbackCurrentWeightLb: fallbackLb
        )
    }

    @Test func noGoalMeansNoPlan() {
        let state = DailyPlanLoader.makeState(
            goal: nil, summary: Self.summary(intake: 1000, burn: 1500),
            averageBurnKcal: 2800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == nil)
        #expect(state.remainingKcal == nil)
        #expect(state.gaugeProgress == 0)
    }

    @Test func maintenanceBudgetIsTheClampedBurn() {
        // Today's 3000 tops the 2800 average — the budget follows
        // (the 2.1.4 fix, now asserted on the complication path).
        let state = DailyPlanLoader.makeState(
            goal: SyncedGoal(
                targetWeightLb: 200, targetDate: Self.now,
                fallbackCurrentWeightLb: nil, mode: GoalMode.maintain
            ),
            summary: Self.summary(intake: 2000, burn: 3000),
            averageBurnKcal: 2800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == 3000)
        #expect(state.remainingKcal == 1000)
        // Gauge shows budget left: 1 - 2000/3000.
        #expect(abs(state.gaugeProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func weightGoalBanksDeficitTowardTheTarget() throws {
        // 10 lb / 100 days off a 2800 burn: 350 deficit, 2450 budget.
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 1000, burn: 1175),
            averageBurnKcal: 2800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(abs(try #require(state.deficitTargetKcal) - 350) < 0.01)
        #expect(abs(try #require(state.dailyBudgetKcal) - 2450) < 0.01)
        // Banked 175 of 350 → half the gauge.
        #expect(abs(state.gaugeProgress - 0.5) < 0.0001)
    }

    @Test func fallbackWeightCarriesThePlanWhenHealthHasNone() {
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(fallbackLb: 200),
            summary: Self.summary(intake: 0, burn: 0),
            averageBurnKcal: 2800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal != nil)
    }

    @Test func noWeightAnywhereMeansNoPlan() {
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 0, burn: 0),
            averageBurnKcal: 2800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == nil)
    }

    @Test func burnFloorOutranksARevisedSummary() {
        // Health revised today's burn down after the day's mark was
        // set: the budget derives from the floor, while the displayed
        // summary keeps the honest lower number.
        let state = DailyPlanLoader.makeState(
            goal: SyncedGoal(
                targetWeightLb: 200, targetDate: Self.now,
                fallbackCurrentWeightLb: nil, mode: GoalMode.maintain
            ),
            summary: Self.summary(intake: 2000, burn: 2796),
            averageBurnKcal: 2500, healthWeightLb: nil,
            todayBurnFloorKcal: 3021,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.dailyBudgetKcal == 3021)
        #expect(state.summary.totalBurnKcal == 2796)
    }

    @Test func gaugeClampsAtBothEnds() {
        // Eaten far past the budget → surplus, gauge floors at 0.
        let over = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 4000, burn: 1000),
            averageBurnKcal: 2800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(over.gaugeProgress == 0)
        // Deficit far past the target → gauge caps at 1.
        let under = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 0, burn: 2000),
            averageBurnKcal: 2800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(under.gaugeProgress == 1)
    }
}
