import Foundation
import WatchKit
import OnigiriKit

@Observable
final class WatchModel {
    private(set) var state: DailyPlanLoader.State = .empty
    /// Day totals for the phone-configured tracked-metric slots, in each
    /// nutrient's label unit — the watch queries its own Health store
    /// (the log itself syncs via Health).
    private(set) var trackedTotals: [Double] = [0, 0]
    /// Today's food entries for the Log page, newest first.
    private(set) var foodLog: [FoodLogEntry] = []
    let sync = WatchSyncReceiver()

    private let health = HealthKitService()
    private var started = false
    /// Double-taps on a slow HealthKit write must not log twice.
    private var isLogging = false
    /// Completed-refresh stamp: page swipes and re-activations fired a
    /// full plan load each (TabView pre-renders neighbors, so one open
    /// plus a swipe could run it 3-4×).
    private var lastRefreshed: Date?
    /// The refresh currently underway, so passive callers can join it —
    /// at launch, start()'s refresh plus the pre-rendered pages' onAppear
    /// used to run three concurrent full query sets before the first
    /// completion could stamp lastRefreshed.
    private var refreshTask: Task<Void, Never>?

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

    /// Passive entry point (page onAppear, scene re-activation): join a
    /// refresh already underway, and skip the query set when fresh —
    /// unless the day rolled over. Logs and start() still call refresh()
    /// directly (post-write data must never piggyback on a pre-write read).
    func refreshIfStale(maxAge: TimeInterval = 30) async {
        if let running = refreshTask {
            await running.value
            return
        }
        if let last = lastRefreshed,
           Date.now.timeIntervalSince(last) < maxAge,
           Calendar.current.isDate(last, inSameDayAs: .now) {
            return
        }
        await refresh()
    }

    func refresh() async {
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        if refreshTask == task {
            refreshTask = nil
        }
    }

    private func performRefresh() async {
        healthDenied = health.sharingDenied()
        // The reads are independent — run them all concurrently.
        async let planRead = DailyPlanLoader.load(goal: sync.goal)
        async let entriesRead = health.todayFoodEntries()
        async let slot1 = slotTotal(slot: 1)
        async let slot2 = slotTotal(slot: 2)
        let totals = await [slot1, slot2]
        state = await planRead
        trackedTotals = totals
        // Newest first straight from the query's sort descriptor.
        let entries = try? await entriesRead
        foodLog = entries ?? []
        // Stamp only when the store actually answered — a transient
        // Health failure must not make refreshIfStale suppress the retry
        // the next page swipe or wrist raise would provide.
        if entries != nil {
            lastRefreshed = .now
        }
    }

    private func slotTotal(slot: Int) async -> Double {
        guard let nutrient = SharedStore.trackedNutrient(slot: slot) else { return 0 }
        return (try? await health.dayTotal(of: nutrient)) ?? 0
    }

    /// Rescale a logged entry to a new calorie count — sodium and the
    /// extended nutrients scale with it (the phone's write-before-delete
    /// edit, kcal-first).
    @discardableResult
    func editEntry(_ entry: FoodLogEntry, kcal: Double) async -> Bool {
        guard !isLogging else { return false }
        isLogging = true
        defer { isLogging = false }
        do {
            let scale = entry.kcal > 0 ? kcal / entry.kcal : 1
            _ = try await health.logFood(
                name: entry.name,
                kcal: kcal,
                sodiumMg: entry.sodiumMg * scale,
                nutrients: entry.nutrients.scaled(by: scale),
                category: entry.category,
                date: entry.date
            )
            try await health.deleteFoodEntry(id: entry.id)
            WKInterfaceDevice.current().play(.success)
            showFlash("✓ \(entry.name) updated", isError: false)
            await refresh()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash("Couldn't save — check Health access", isError: true)
            await refresh()
            return false
        }
    }

    @discardableResult
    func deleteEntry(_ entry: FoodLogEntry) async -> Bool {
        guard !isLogging else { return false }
        isLogging = true
        defer { isLogging = false }
        do {
            try await health.deleteFoodEntry(id: entry.id)
            WKInterfaceDevice.current().play(.success)
            showFlash("Removed \(entry.name)", isError: false)
            await refresh()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash("Couldn't remove — check Health access", isError: true)
            return false
        }
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
