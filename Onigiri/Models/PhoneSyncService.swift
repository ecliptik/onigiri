import Foundation
import SwiftData
import WatchConnectivity
import OnigiriKit

/// Pushes the library + settings to the watch as the WatchConnectivity
/// application context (latest-wins; delivered when the watch is reachable).
final class PhoneSyncService: NSObject, WCSessionDelegate {
    static let shared = PhoneSyncService()

    private var onActivate: (@MainActor () -> Void)?

    func activate(onActivate: @escaping @MainActor () -> Void) {
        guard WCSession.isSupported() else { return }
        self.onActivate = onActivate
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            Task { @MainActor in onActivate() }
        } else {
            session.activate()
        }
    }

    /// Snapshot meals, goal, and water settings; mirror them into the App
    /// Group defaults (the widget extension reads that — keeps SwiftData out
    /// of its memory-capped process), and send them to the watch if paired.
    @MainActor
    func push(from context: ModelContext) {
        let meals = ((try? context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .map { SyncedMeal(
                id: $0.uuid, name: $0.name, kcal: $0.totalKcal, sodiumMg: $0.totalSodiumMg,
                category: $0.category, nutrients: $0.totalNutrients
            ) }
        let goal = ((try? context.fetch(FetchDescriptor<GoalSettings>())) ?? []).first
            .map { SyncedGoal(
                targetWeightLb: $0.targetWeightLb,
                targetDate: $0.targetDate,
                fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb
            ) }

        let balanceStyle = SharedStore.defaults.string(forKey: SharedStore.balanceStyleKey) ?? "balance"
        let foodIcon = SharedStore.defaults.string(forKey: SharedStore.foodIconKey) ?? "sfFork"
        let waterIcon = SharedStore.defaults.string(forKey: SharedStore.waterIconKey) ?? "sfDrop"
        let rewardIcon = SharedStore.defaults.string(forKey: SharedStore.rewardIconKey) ?? "onigiri"
        // The tracked-metric slots ride verbatim (targets stringified);
        // the watch's metrics page mirrors the phone's configuration.
        let trackedSettings: [String: String] = Dictionary(
            uniqueKeysWithValues: WatchSync.trackedMetricKeys.compactMap { key in
                if let string = SharedStore.defaults.string(forKey: key) {
                    return (key, string)
                }
                let number = SharedStore.defaults.double(forKey: key)
                return number > 0 ? (key, String(number)) : nil
            }
        )
        WatchSync.store(SyncPayload(
            meals: meals,
            goal: goal.map(GoalUpdate.set) ?? .clear,
            waterServingOz: SharedStore.waterServingOz,
            waterGoalOz: SharedStore.waterGoalOz,
            balanceStyle: balanceStyle,
            foodIcon: foodIcon,
            waterIcon: waterIcon,
            rewardIcon: rewardIcon,
            trackedMetricSettings: trackedSettings,
            sodiumLimitMg: SharedStore.sodiumLimitMg
        ))

        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled
        else { return }
        try? WCSession.default.updateApplicationContext(WatchSync.makeContext(
            meals: meals,
            goal: goal,
            waterServingOz: SharedStore.waterServingOz,
            waterGoalOz: SharedStore.waterGoalOz,
            balanceStyle: balanceStyle,
            foodIcon: foodIcon,
            waterIcon: waterIcon,
            rewardIcon: rewardIcon,
            trackedMetricSettings: trackedSettings,
            sodiumLimitMg: SharedStore.sodiumLimitMg
        ))
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.onActivate?()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
