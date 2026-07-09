import Foundation
import SwiftData
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
    static func load() async -> DaySnapshot {
        let health = HealthKitService()
        let summary = (try? await health.todaySummary()) ?? .zero

        var deficitTarget: Double?
        var remaining: Double?
        var progress: Double = 0

        if let container = try? SharedStore.modelContainer(),
           let goal = try? container.mainContext.fetch(FetchDescriptor<GoalSettings>()).first {
            let healthWeight = (try? await health.latestBodyMassLb()) ?? nil
            if let weight = healthWeight ?? goal.fallbackCurrentWeightLb {
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
                deficitTarget = plan.requiredDailyDeficit
                remaining = plan.dailyBudget - summary.intakeKcal
                progress = plan.requiredDailyDeficit > 0
                    ? max(0, min(1, -summary.balanceKcal / plan.requiredDailyDeficit))
                    : 1
            }
        }

        return DaySnapshot(
            summary: summary,
            deficitTargetKcal: deficitTarget,
            remainingKcal: remaining,
            gaugeProgress: progress,
            waterGoalOz: SharedStore.waterGoalOz
        )
    }
}
