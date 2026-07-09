import Foundation
import WatchKit
import WidgetKit
import OnigiriKit

@Observable
final class WatchModel {
    private(set) var state: DailyPlanLoader.State = .empty
    let sync = WatchSyncReceiver()

    private let health = HealthKitService()
    private var started = false

    var waterServingOz: Double { SharedStore.waterServingOz }
    var waterGoalOz: Double { SharedStore.waterGoalOz }

    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        sync.activate()
        guard HealthKitService.isAvailable else { return }
        if (try? await health.shouldRequestAuthorization()) == true {
            try? await health.requestAuthorization()
        }
        await refresh()
    }

    func refresh() async {
        state = await DailyPlanLoader.load(goal: sync.goal)
    }

    func logWater() async {
        do {
            try await health.logWater(oz: waterServingOz)
            WKInterfaceDevice.current().play(.success)
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func log(_ meal: SyncedMeal) async {
        do {
            try await health.logFood(name: meal.name, kcal: meal.kcal, sodiumMg: meal.sodiumMg)
            WKInterfaceDevice.current().play(.success)
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
