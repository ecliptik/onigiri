import Foundation

/// Combines today's HealthKit summary with a (possibly synced) goal into the
/// numbers the watch app and complications render. Plan assembly
/// (`makeState`) is pure and lives outside the HealthKit guard so the
/// macOS test host can reach it; only the fetch layer needs the store.
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

    /// Assemble the rendered state from already-fetched Health numbers.
    /// Maintenance: eat what you burn — deficitTarget stays nil (the
    /// any-deficit badge rule, no "% of goal" captions) and the gauge
    /// shows budget left. A weight goal banks deficit toward the target;
    /// without a current weight anywhere there is no plan. Both modes
    /// ride the shared clamped-burn derivation.
    public static func makeState(
        goal: SyncedGoal?,
        summary: DailyEnergySummary,
        averageBurnKcal: Double?,
        healthWeightLb: Double?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> State {
        guard let goal else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        if goal.isMaintenance {
            let burn = CalorieBudget.expectedDailyBurn(
                averageKcal: averageBurnKcal, todayActualKcal: summary.totalBurnKcal
            )
            let plan = CalorieBudget.maintenancePlan(averageDailyBurn: burn)
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
        guard let plan = CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: healthWeightLb ?? goal.fallbackCurrentWeightLb,
            targetWeightLb: goal.targetWeightLb,
            targetDate: goal.targetDate,
            averageDailyBurnKcal: averageBurnKcal,
            todayActualBurnKcal: summary.totalBurnKcal,
            calendar: calendar,
            now: now
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

#if canImport(HealthKit)
/// The reads the loader performs — injectable so tests can stub the
/// store (the audit's HealthKitService-injection gap, scoped to the
/// loader's surface).
@MainActor
public protocol HealthPlanReading: Sendable {
    func todaySummary() async throws -> DailyEnergySummary
    func averageDailyBurnKcal() async throws -> Double?
    func latestBodyMassLb() async throws -> Double?
}

extension HealthKitService: HealthPlanReading {
    // Defaulted-parameter methods can't witness protocol requirements;
    // these forward to the real implementations.
    public func todaySummary() async throws -> DailyEnergySummary {
        try await todaySummary(now: .now)
    }

    public func averageDailyBurnKcal() async throws -> Double? {
        try await averageDailyBurnKcal(days: 14, now: .now)
    }
}

public extension DailyPlanLoader {
    static func load(
        goal: SyncedGoal?,
        health: any HealthPlanReading = HealthKitService()
    ) async -> State {
        let state = await computeState(goal: goal, health: health)
        // Every plan load stamps today's target, so history keeps being
        // judged by the goal in force that day even after the goal (or
        // the weight behind it) changes.
        DeficitTargetHistory.recordToday(targetKcal: state.deficitTargetKcal)
        return state
    }

    private static func computeState(
        goal: SyncedGoal?,
        health: any HealthPlanReading
    ) async -> State {
        guard let goal else {
            let summary = (try? await health.todaySummary()) ?? .zero
            return makeState(goal: nil, summary: summary, averageBurnKcal: nil, healthWeightLb: nil)
        }
        // The reads are independent — run them concurrently; this path
        // is complication/widget refresh latency.
        async let summaryRead = health.todaySummary()
        async let burnRead = health.averageDailyBurnKcal()
        if goal.isMaintenance {
            // The current weight plays no part — don't query it.
            return makeState(
                goal: goal,
                summary: (try? await summaryRead) ?? .zero,
                averageBurnKcal: (try? await burnRead) ?? nil,
                healthWeightLb: nil
            )
        }
        async let weightRead = health.latestBodyMassLb()
        return makeState(
            goal: goal,
            summary: (try? await summaryRead) ?? .zero,
            averageBurnKcal: (try? await burnRead) ?? nil,
            healthWeightLb: (try? await weightRead) ?? nil
        )
    }
}
#endif
