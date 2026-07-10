#if canImport(HealthKit)
import Foundation

/// Combines today's HealthKit summary with a (possibly synced) goal into the
/// numbers the watch app and complications render.
@MainActor
public enum DailyPlanLoader {
    public struct State: Sendable {
        public let summary: DailyEnergySummary
        public let deficitTargetKcal: Double?
        /// 0...1 fill of the onigiri gauge (banked deficit / daily target).
        public let gaugeProgress: Double
        /// Intake budget for the day (average burn − required deficit).
        public let dailyBudgetKcal: Double?

        public init(
            summary: DailyEnergySummary,
            deficitTargetKcal: Double?,
            gaugeProgress: Double,
            dailyBudgetKcal: Double? = nil
        ) {
            self.summary = summary
            self.deficitTargetKcal = deficitTargetKcal
            self.gaugeProgress = gaugeProgress
            self.dailyBudgetKcal = dailyBudgetKcal
        }

        /// kcal still available to eat today, when a plan exists.
        public var remainingKcal: Double? {
            dailyBudgetKcal.map { $0 - summary.intakeKcal }
        }

        public static let empty = State(summary: .zero, deficitTargetKcal: nil, gaugeProgress: 0)
    }

    public static func load(goal: SyncedGoal?) async -> State {
        let health = HealthKitService()
        guard let goal else {
            let summary = (try? await health.todaySummary()) ?? .zero
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        // The three reads are independent — run them concurrently; this
        // path is complication/widget refresh latency.
        async let summaryRead = health.todaySummary()
        async let weightRead = health.latestBodyMassLb()
        async let burnRead = health.averageDailyBurnKcal()
        let summary = (try? await summaryRead) ?? .zero
        let healthWeight = (try? await weightRead) ?? nil
        guard let weight = healthWeight ?? goal.fallbackCurrentWeightLb else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let averageBurn = ((try? await burnRead) ?? nil)
            ?? max(summary.totalBurnKcal, 2000)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: goal.targetDate
        ).day ?? 0
        let plan = CalorieBudget.plan(
            currentWeightLb: weight,
            targetWeightLb: goal.targetWeightLb,
            daysRemaining: days,
            averageDailyBurn: averageBurn
        )
        let progress = plan.requiredDailyDeficit > 0
            ? max(0, min(1, -summary.balanceKcal / plan.requiredDailyDeficit))
            : 1
        return State(
            summary: summary,
            deficitTargetKcal: plan.requiredDailyDeficit,
            gaugeProgress: progress,
            dailyBudgetKcal: plan.dailyBudget
        )
    }
}
#endif
