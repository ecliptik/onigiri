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
        let state = await computePlan(goal: goal)
        // Every plan load stamps today's target, so history keeps being
        // judged by the goal in force that day even after the goal (or
        // the weight behind it) changes.
        DeficitTargetHistory.recordToday(targetKcal: state.deficitTargetKcal)
        return state
    }

    private static func computePlan(goal: SyncedGoal?) async -> State {
        let health = HealthKitService()
        guard let goal else {
            let summary = (try? await health.todaySummary()) ?? .zero
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        // The reads are independent — run them concurrently; this path
        // is complication/widget refresh latency.
        async let summaryRead = health.todaySummary()
        async let burnRead = health.averageDailyBurnKcal()
        if goal.isMaintenance {
            // Maintenance: eat what you burn. deficitTarget stays nil
            // (any-deficit badge rule, and no "% of goal" captions);
            // the gauge shows the budget still left to eat. The current
            // weight plays no part — don't query it.
            let summary = (try? await summaryRead) ?? .zero
            // The shared clamp: never less than today's actual burn, or
            // the widget/complication read "0" while the phone (and
            // reality) show room left.
            let averageBurn = CalorieBudget.expectedDailyBurn(
                averageKcal: (try? await burnRead) ?? nil,
                todayActualKcal: summary.totalBurnKcal
            )
            let plan = CalorieBudget.maintenancePlan(averageDailyBurn: averageBurn)
            let progress = plan.dailyBudget > 0
                ? max(0, min(1, 1 - summary.intakeKcal / plan.dailyBudget))
                : 0
            return State(
                summary: summary,
                deficitTargetKcal: nil,
                gaugeProgress: progress,
                dailyBudgetKcal: plan.dailyBudget
            )
        }
        async let weightRead = health.latestBodyMassLb()
        let summary = (try? await summaryRead) ?? .zero
        let healthWeight = (try? await weightRead) ?? nil
        // The shared derivation (clamped burn + days-to-target); nil
        // only when no current weight exists anywhere.
        guard let plan = CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: healthWeight ?? goal.fallbackCurrentWeightLb,
            targetWeightLb: goal.targetWeightLb,
            targetDate: goal.targetDate,
            averageDailyBurnKcal: (try? await burnRead) ?? nil,
            todayActualBurnKcal: summary.totalBurnKcal
        ) else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
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
