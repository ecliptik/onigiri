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
        /// Intake budget for the day (the day's own burn − required deficit).
        public let dailyBudgetKcal: Double?
        /// The burn the budget was cut from (`DayBudget.dayBurn`) — the
        /// figure every verdict-shaped number on this state must read,
        /// so the gauge, the goal line and the headline can't answer the
        /// same question differently. nil when there's no plan.
        public let dayBurnKcal: Double?

        public init(
            summary: DailyEnergySummary,
            deficitTargetKcal: Double?,
            gaugeProgress: Double,
            dailyBudgetKcal: Double? = nil,
            dayBurnKcal: Double? = nil
        ) {
            self.summary = summary
            self.deficitTargetKcal = deficitTargetKcal
            self.gaugeProgress = gaugeProgress
            self.dailyBudgetKcal = dailyBudgetKcal
            self.dayBurnKcal = dayBurnKcal
        }

        /// kcal still available to eat today, when a plan exists.
        public var remainingKcal: Double? {
            dailyBudgetKcal.map { $0 - summary.intakeKcal }
        }

        /// The day's deficit on the budget's own burn, positive for a
        /// deficit. Falls back to the raw measured balance only where
        /// there is no plan to disagree with.
        public var deficitKcal: Double {
            DayBudget.deficit(
                intakeKcal: summary.intakeKcal,
                dayBurnKcal: dayBurnKcal ?? summary.totalBurnKcal
            )
        }

        public static let empty = State(summary: .zero, deficitTargetKcal: nil, gaugeProgress: 0)
    }

    /// Assemble the rendered state from already-fetched Health numbers.
    /// Maintenance: eat what you burn — deficitTarget stays nil (the
    /// any-deficit badge rule, no "% of goal" captions) and the gauge
    /// shows budget left. A weight goal banks deficit toward the target;
    /// without a current weight anywhere there is no plan.
    ///
    /// Both modes ride the SAME burn figure the phone does
    /// (`DayBudget.dayBurn`): resting credited up front — measured,
    /// floored by the body-metric estimate — plus the active energy
    /// actually earned. The trailing-average forecast is gone. It lived
    /// here longer than on the phone, which is precisely why this had to
    /// move before shipping: the widgets and the watch would have gone on
    /// quoting an average-based budget while Today quoted the earned one.
    public static func makeState(
        goal: SyncedGoal?,
        summary: DailyEnergySummary,
        /// Full-day resting from body metrics (`BasalEstimate.restingKcal`),
        /// the floor under the day's resting credit. nil when Health can't
        /// describe the body well enough — measured resting then stands
        /// alone, which is a documented shortfall, not an error.
        estimatedRestingKcal: Double?,
        healthWeightLb: Double?,
        /// The day-ratcheted day burn (TodayBurnFloor) when the caller has
        /// one — the budget derives from it while the summary keeps the
        /// honest display numbers. nil = derive straight from the summary,
        /// the pure pre-ratchet behavior the tests pin.
        todayBurnFloorKcal: Double? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> State {
        guard let goal else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let dayBurn = todayBurnFloorKcal ?? DayBudget.dayBurn(
            activeKcal: summary.activeBurnKcal,
            restingKcal: summary.restingBurnKcal,
            estimatedRestingKcal: estimatedRestingKcal
        )
        // Nothing measured and no estimate to floor it with: a budget of
        // "0 minus the target" would invent a huge overage, so the
        // budget-shaped UI stands down (TodayView's guard). The deficit
        // target still stamps history — the goal was in force either way.
        let hasBurn = dayBurn > 0
        if goal.isMaintenance {
            let plan = CalorieBudget.completedDayPlan(
                dayBurnKcal: dayBurn, requiredDailyDeficit: 0
            )
            let progress = plan.dailyBudget > 0
                ? max(0, min(1, 1 - summary.intakeKcal / plan.dailyBudget))
                : 0
            return State(
                summary: summary,
                deficitTargetKcal: nil,
                gaugeProgress: progress,
                dailyBudgetKcal: hasBurn ? plan.dailyBudget : nil,
                dayBurnKcal: hasBurn ? dayBurn : nil
            )
        }
        guard let deficit = CalorieBudget.requiredDailyDeficit(
            currentWeightLb: healthWeightLb ?? goal.fallbackCurrentWeightLb,
            targetWeightLb: goal.targetWeightLb,
            targetDate: goal.targetDate,
            calendar: calendar,
            now: now
        ) else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: dayBurn, requiredDailyDeficit: deficit
        )
        // Banked on the SAME burn the budget was cut from, so the gauge
        // can't sit part-full while the number beside it says the day is
        // already inside its budget.
        let banked = DayBudget.deficit(intakeKcal: summary.intakeKcal, dayBurnKcal: dayBurn)
        let progress = plan.requiredDailyDeficit > 0
            ? max(0, min(1, banked / plan.requiredDailyDeficit))
            : 1
        return State(
            summary: summary,
            deficitTargetKcal: plan.requiredDailyDeficit,
            gaugeProgress: progress,
            dailyBudgetKcal: hasBurn ? plan.dailyBudget : nil,
            dayBurnKcal: hasBurn ? dayBurn : nil
        )
    }

    /// One plan input resolved between the phone's synced copy and the
    /// local Health read. The synced value wins while its day stamp is
    /// today or yesterday: the phone's store holds full history, while
    /// watchOS purges old samples — a weigh-in older than the watch's
    /// window is invisible there, and the two devices' plans drift apart.
    nonisolated static func planInput(
        synced: (value: Double, day: String)?,
        local: Double?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        guard let synced, WatchSync.isRecentDay(synced.day, calendar: calendar, now: now)
        else { return local }
        return synced.value
    }
}

#if canImport(HealthKit)
/// The reads the loader performs — injectable so tests can stub the
/// store (the audit's HealthKitService-injection gap, scoped to the
/// loader's surface).
@MainActor
public protocol HealthPlanReading: Sendable {
    func todaySummary() async throws -> DailyEnergySummary
    func latestBodyMassLb() async throws -> Double?
    /// Height/age/sex — with weight, the inputs the resting estimate
    /// needs. The trailing burn average it replaced is no longer a plan
    /// input on any surface.
    func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex)
}

extension HealthKitService: HealthPlanReading {
    // Defaulted-parameter methods can't witness protocol requirements;
    // this forwards to the real implementation.
    public func todaySummary() async throws -> DailyEnergySummary {
        try await todaySummary(now: .now)
    }
}

public extension DailyPlanLoader {
    static func load(
        goal: SyncedGoal?,
        health: any HealthPlanReading = HealthKitService()
    ) async -> State {
        let state = await computeState(goal: goal, health: health)
        // Every plan load stamps today's rule, so history keeps being
        // judged by the goal in force that day even after the goal (or
        // the weight behind it) changes.
        DeficitTargetHistory.recordToday(
            targetKcal: state.deficitTargetKcal,
            isMaintenance: goal?.isMaintenance ?? false
        )
        return state
    }

    private static func computeState(
        goal: SyncedGoal?,
        health: any HealthPlanReading
    ) async -> State {
        guard let goal else {
            let summary = (try? await health.todaySummary()) ?? .zero
            return makeState(
                goal: nil, summary: summary,
                estimatedRestingKcal: nil, healthWeightLb: nil
            )
        }
        // The reads are independent — run them concurrently; this path
        // is complication/widget refresh latency. Weight is read even in
        // maintenance now: it isn't a plan input there, but the resting
        // estimate that floors the day's burn is built from it.
        async let summaryRead = health.todaySummary()
        async let weightRead = health.latestBodyMassLb()
        async let profileRead = health.bodyProfile()
        let summary = (try? await summaryRead) ?? .zero
        let weightLb = resolvedWeight((try? await weightRead) ?? nil)
        let profile = await profileRead
        let estimatedResting: Double? = {
            guard let heightCm = profile.heightCm, let age = profile.ageYears,
                  let weightLb else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm,
                ageYears: age, sex: profile.sex)
        }()
        // Ratchet the DAY burn, not the raw total: under measured-only
        // active energy the guard against Health revising burn downward
        // mid-day matters more, not less.
        let dayBurn = DayBudget.dayBurn(
            activeKcal: summary.activeBurnKcal,
            restingKcal: summary.restingBurnKcal,
            estimatedRestingKcal: estimatedResting
        )
        return makeState(
            goal: goal,
            summary: summary,
            estimatedRestingKcal: estimatedResting,
            healthWeightLb: weightLb,
            todayBurnFloorKcal: TodayBurnFloor.ratcheted(dayBurn)
        )
    }

    /// On the watch, prefer the phone's synced weight while fresh (see
    /// `planInput`); everywhere else the local store IS the phone's.
    private static func resolvedWeight(_ local: Double?) -> Double? {
        #if os(watchOS)
        return planInput(
            synced: WatchSync.syncedPlanWeight().map { ($0.lb, $0.day) }, local: local
        )
        #else
        return local
        #endif
    }
}
#endif
