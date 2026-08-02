import Foundation
import Testing
@testable import OnigiriKit

/// Plan assembly for the watch/widget surfaces — every branch of
/// makeState. This is the path that used to carry the trailing-average
/// budget to complications after the phone had already moved to the
/// day's own burn; these pin the two together.
@MainActor
struct DailyPlanLoaderTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9))!

    /// A day's measured channels. The split matters now: resting is
    /// floored by the estimate, active never is.
    private static func summary(
        intake: Double, active: Double, resting: Double
    ) -> DailyEnergySummary {
        DailyEnergySummary(
            intakeKcal: intake, activeBurnKcal: active,
            restingBurnKcal: resting, sodiumMg: 0, waterOz: 0
        )
    }

    private static func weightGoal(fallbackLb: Double? = nil) -> SyncedGoal {
        SyncedGoal(
            targetWeightLb: 190,
            targetDate: cal.date(byAdding: .day, value: 100, to: now)!,
            fallbackCurrentWeightLb: fallbackLb
        )
    }

    private static func maintenanceGoal() -> SyncedGoal {
        SyncedGoal(
            targetWeightLb: 200, targetDate: now,
            fallbackCurrentWeightLb: nil, mode: GoalMode.maintain
        )
    }

    @Test func noGoalMeansNoPlan() {
        let state = DailyPlanLoader.makeState(
            goal: nil, summary: Self.summary(intake: 1000, active: 450, resting: 1050),
            estimatedRestingKcal: 1800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == nil)
        #expect(state.remainingKcal == nil)
        #expect(state.gaugeProgress == 0)
    }

    @Test func maintenanceBudgetIsTheDaysOwnBurn() {
        // Resting has already passed the estimate, so the day's burn is
        // simply what Health measured: 900 + 2100.
        let state = DailyPlanLoader.makeState(
            goal: Self.maintenanceGoal(),
            summary: Self.summary(intake: 2000, active: 900, resting: 2100),
            estimatedRestingKcal: 1800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == 3000)
        #expect(state.remainingKcal == 1000)
        // Gauge shows budget left: 1 - 2000/3000.
        #expect(abs(state.gaugeProgress - (1.0 / 3.0)) < 0.0001)
    }

    /// The acceptance test, on the surface it was missing from: at 9am
    /// the whole day's resting is already credited, so a morning that has
    /// measured barely any of it still quotes a real budget rather than
    /// something near zero.
    @Test func restingIsCreditedUpFrontAtBreakfast() throws {
        let state = DailyPlanLoader.makeState(
            goal: Self.maintenanceGoal(),
            summary: Self.summary(intake: 400, active: 50, resting: 610),
            estimatedRestingKcal: 1_831, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        // 50 earned + the full 1,831 baseline, not 660.
        #expect(try #require(state.dailyBudgetKcal) == 1_881)
        #expect(try #require(state.remainingKcal) == 1_481)
    }

    /// The other half of the rule: a day with no watch keeps its
    /// baseline and earns nothing on top.
    @Test func unwornDayKeepsTheBaselineAndEarnsNoActivity() throws {
        let worn = DailyPlanLoader.makeState(
            goal: Self.maintenanceGoal(),
            summary: Self.summary(intake: 0, active: 500, resting: 1_831),
            estimatedRestingKcal: 1_831, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        let unworn = DailyPlanLoader.makeState(
            goal: Self.maintenanceGoal(),
            summary: Self.summary(intake: 0, active: 0, resting: 0),
            estimatedRestingKcal: 1_831, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(try #require(worn.dailyBudgetKcal) == 2_331)
        #expect(try #require(unworn.dailyBudgetKcal) == 1_831)
    }

    @Test func weightGoalBanksDeficitTowardTheTarget() throws {
        // 10 lb / 100 days: a 350 deficit. Against a 2,800 day burn
        // (700 earned + a 2,100 baseline) that's a 2,450 budget.
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 1000, active: 700, resting: 2100),
            estimatedRestingKcal: 1800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(abs(try #require(state.deficitTargetKcal) - 350) < 0.01)
        #expect(abs(try #require(state.dailyBudgetKcal) - 2450) < 0.01)
    }

    /// The identity the whole change turns on: staying inside the budget
    /// is exactly banking the required deficit, because both sides read
    /// the same day burn.
    @Test func stayingInBudgetIsExactlyBankingTheDeficit() throws {
        let summary = Self.summary(intake: 2450, active: 700, resting: 2100)
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: summary,
            estimatedRestingKcal: 1800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        let remaining = try #require(state.remainingKcal)
        let target = try #require(state.deficitTargetKcal)
        let banked = -summary.balanceKcal
        #expect(abs(remaining) < 0.01)
        #expect(abs(banked - target) < 0.01)
    }

    @Test func fallbackWeightCarriesThePlanWhenHealthHasNone() {
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(fallbackLb: 200),
            summary: Self.summary(intake: 0, active: 0, resting: 0),
            estimatedRestingKcal: 1800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal != nil)
    }

    @Test func noWeightAnywhereMeansNoPlan() {
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 0, active: 0, resting: 0),
            estimatedRestingKcal: 1800, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal == nil)
        #expect(state.dailyBudgetKcal == nil)
    }

    /// No measured burn and no estimate to floor it with: the target
    /// still stamps history, but nothing budget-shaped renders — a
    /// budget of "0 minus the target" would invent a huge overage.
    @Test func noBurnAtAllWithholdsTheBudgetButKeepsTheTarget() {
        let state = DailyPlanLoader.makeState(
            goal: Self.weightGoal(fallbackLb: 200),
            summary: Self.summary(intake: 0, active: 0, resting: 0),
            estimatedRestingKcal: nil, healthWeightLb: nil,
            calendar: Self.cal, now: Self.now
        )
        #expect(state.deficitTargetKcal != nil)
        #expect(state.dailyBudgetKcal == nil)
    }

    @Test func burnFloorOutranksARevisedSummary() {
        // Health revised today's burn down after the day's mark was
        // set: the budget derives from the floor, while the displayed
        // summary keeps the honest lower number.
        let state = DailyPlanLoader.makeState(
            goal: Self.maintenanceGoal(),
            summary: Self.summary(intake: 2000, active: 696, resting: 2100),
            estimatedRestingKcal: 1800, healthWeightLb: nil,
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
            summary: Self.summary(intake: 4000, active: 200, resting: 800),
            estimatedRestingKcal: 800, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(over.gaugeProgress == 0)
        // Deficit far past the target → gauge caps at 1.
        let under = DailyPlanLoader.makeState(
            goal: Self.weightGoal(),
            summary: Self.summary(intake: 0, active: 400, resting: 1600),
            estimatedRestingKcal: 1600, healthWeightLb: 200,
            calendar: Self.cal, now: Self.now
        )
        #expect(under.gaugeProgress == 1)
    }
}
