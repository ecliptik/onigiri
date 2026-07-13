import Foundation
import WatchKit
import WidgetKit
import OnigiriKit

@Observable
final class WatchModel {
    private(set) var state: DailyPlanLoader.State = .empty
    /// Day totals for the phone-configured tracked-metric slots, in each
    /// nutrient's label unit — the watch queries its own Health store
    /// (the log itself syncs via Health).
    private(set) var trackedTotals: [Double] = [0, 0]
    let sync = WatchSyncReceiver()

    private let health = HealthKitService()
    private var started = false
    /// Double-taps on a slow HealthKit write must not log twice.
    private var isLogging = false

    /// Transient line under the buttons: haptics alone made a failed
    /// log indistinguishable from a successful one.
    private(set) var flash: String?
    private(set) var flashIsError = false
    private var flashGeneration = 0
    /// Write access denied — zeros forever otherwise, with no hint.
    private(set) var healthDenied = false

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
        healthDenied = health.sharingDenied()
        var totals: [Double] = [0, 0]
        for slot in 1...2 {
            if let nutrient = SharedStore.trackedNutrient(slot: slot) {
                totals[slot - 1] = (try? await health.dayTotal(of: nutrient)) ?? 0
            }
        }
        trackedTotals = totals
    }

    @discardableResult
    func logWater() async -> Bool {
        guard !isLogging else { return false }
        isLogging = true
        defer { isLogging = false }
        do {
            try await health.logWater(oz: waterServingOz)
            WKInterfaceDevice.current().play(.success)
            showFlash(
                "+\(waterServingOz.formatted(.number.precision(.fractionLength(0)))) oz ✓",
                isError: false
            )
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash("Couldn't log — check Health access", isError: true)
            return false
        }
    }

    @discardableResult
    func log(_ meal: SyncedMeal) async -> Bool {
        guard !isLogging else { return false }
        isLogging = true
        defer { isLogging = false }
        do {
            // Carry the meal's slot and nutrients like the phone does; old
            // payloads without them fall back to time-of-day inference.
            try await health.logFood(
                name: meal.name, kcal: meal.kcal, sodiumMg: meal.sodiumMg,
                nutrients: meal.nutrients ?? NutrientValues(),
                category: meal.category.flatMap(FoodCategory.init(rawValue:))
            )
            WKInterfaceDevice.current().play(.success)
            showFlash("✓ \(meal.name)", isError: false)
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash("Couldn't log — check Health access", isError: true)
            return false
        }
    }

    private func showFlash(_ message: String, isError: Bool) {
        flashGeneration += 1
        let generation = flashGeneration
        flash = message
        flashIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(isError ? 4 : 2))
            if generation == flashGeneration { flash = nil }
        }
    }
}
