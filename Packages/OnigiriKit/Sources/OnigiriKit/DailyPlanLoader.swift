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

        public init(summary: DailyEnergySummary, deficitTargetKcal: Double?, gaugeProgress: Double) {
            self.summary = summary
            self.deficitTargetKcal = deficitTargetKcal
            self.gaugeProgress = gaugeProgress
        }

        public static let empty = State(summary: .zero, deficitTargetKcal: nil, gaugeProgress: 0)
    }

    public static func load(goal: SyncedGoal?) async -> State {
        let health = HealthKitService()
        let summary = (try? await health.todaySummary()) ?? .zero
        guard let goal else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let healthWeight = (try? await health.latestBodyMassLb()) ?? nil
        guard let weight = healthWeight ?? goal.fallbackCurrentWeightLb else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let averageBurn = ((try? await health.averageDailyBurnKcal()) ?? nil)
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
            gaugeProgress: progress
        )
    }
}
#endif
