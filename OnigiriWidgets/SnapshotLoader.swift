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
}

@MainActor
enum SnapshotLoader {
    /// The widget process is memory-capped, so it must not open SwiftData.
    /// The phone mirrors the goal into the App Group on every sync push;
    /// the shared DailyPlanLoader does the rest, like the watch.
    static func load() async -> DaySnapshot {
        let state = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        return DaySnapshot(
            summary: state.summary,
            deficitTargetKcal: state.deficitTargetKcal,
            remainingKcal: state.remainingKcal,
            gaugeProgress: state.gaugeProgress,
            waterGoalOz: SharedStore.waterGoalOz
        )
    }
}
