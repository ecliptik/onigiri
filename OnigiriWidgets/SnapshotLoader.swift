import Foundation
import OnigiriKit

/// Everything a widget needs to render one moment of the day.
struct DaySnapshot {
    var summary: DailyEnergySummary
    var deficitTargetKcal: Double?
    var remainingKcal: Double?
    /// 0...1 fill of the onigiri gauge (banked deficit / daily target).
    var gaugeProgress: Double
    var waterGoalOz: Double
    /// Health access never granted — a confident green "0 kcal" before
    /// setup was indistinguishable from a genuinely balanced day.
    var needsSetup = false
    /// Maintenance mode's gauge counts DOWN from a full budget (share
    /// left to eat), the deficit gauge counts UP from zero — the
    /// midnight pre-render below must know which way is "fresh day".
    var isMaintenance = false

    static let placeholder = DaySnapshot(
        summary: DailyEnergySummary(
            intakeKcal: 1280, activeBurnKcal: 385, restingBurnKcal: 1120,
            sodiumMg: 1780, waterOz: 36
        ),
        deficitTargetKcal: 583,
        remainingKcal: 437,
        gaugeProgress: 0.38,
        waterGoalOz: 64
    )

    /// The plan-state view of this snapshot, for the shared accessory
    /// views (budget reconstructed: remaining was budget − intake).
    var planState: DailyPlanLoader.State {
        DailyPlanLoader.State(
            summary: summary,
            deficitTargetKcal: deficitTargetKcal,
            gaugeProgress: gaugeProgress,
            dailyBudgetKcal: remainingKcal.map { $0 + summary.intakeKcal }
        )
    }

    /// The just-after-midnight render: nothing eaten or burned yet, the
    /// same plan. Pre-rendered into the timeline so yesterday's numbers
    /// never show into the new day while WidgetKit waits out its budget.
    var newDay: DaySnapshot {
        DaySnapshot(
            summary: .zero,
            deficitTargetKcal: deficitTargetKcal,
            // The full budget again: remaining was budget − intake.
            remainingKcal: remainingKcal.map { $0 + summary.intakeKcal },
            // Deficit gauges start the day empty (nothing banked);
            // the maintenance gauge starts FULL (whole budget left) —
            // zero here rendered an empty onigiri all morning.
            gaugeProgress: isMaintenance ? 1 : 0,
            waterGoalOz: waterGoalOz,
            needsSetup: needsSetup,
            isMaintenance: isMaintenance
        )
    }
}

/// Next midnight, and whether it lands inside the standard 30-minute
/// refresh window (when it does, the timeline pre-renders the zeroed
/// entry and reloads at midnight instead).
func nextMidnight(after now: Date) -> Date? {
    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
}

@MainActor
enum SnapshotLoader {
    /// The widget process is memory-capped, so it must not open SwiftData.
    /// The phone mirrors the goal into the App Group on every sync push;
    /// the shared DailyPlanLoader does the rest, like the watch.
    static func load() async -> DaySnapshot {
        let needsSetup = await PlanCache.needsSetup()
        let goal = WatchSync.loadGoal()
        let state = await PlanCache.state(goal: goal)
        return DaySnapshot(
            summary: state.summary,
            deficitTargetKcal: state.deficitTargetKcal,
            remainingKcal: state.remainingKcal,
            gaugeProgress: state.gaugeProgress,
            waterGoalOz: SharedStore.waterGoalOz,
            needsSetup: needsSetup,
            isMaintenance: goal?.isMaintenance ?? false
        )
    }
}
