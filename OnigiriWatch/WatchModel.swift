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
        #if DEBUG
        // Screenshot/QA aid: seed this watch's OWN HealthKit with a
        // realistic day so the home headline shows plausible totals on the
        // sim. Uses plain logFood/logWater on the REGULAR write auth (which
        // auto-grants on the sim, no sheet) — NOT seedSampleData(), whose
        // requestDebugSeedAuthorization pops a Health sheet the watch sim
        // can't be tapped to grant. Paired-sim sharing gives the watch burn
        // but not the phone's food, so without this the headline reads
        // intake=0.
        if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
            try? await health.requestAuthorization()
            _ = try? await health.logFood(name: "Avocado toast", kcal: 420, sodiumMg: 620, category: .breakfast)
            _ = try? await health.logFood(name: "Chicken bowl", kcal: 610, sodiumMg: 880, category: .lunch)
            _ = try? await health.logFood(name: "Trail mix", kcal: 205, sodiumMg: 120, category: .snack)
            _ = try? await health.logWater(oz: 24)
            await refresh()
            return
        }
        #endif
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
            let newId = try await health.logFood(
                name: entry.name,
                kcal: kcal,
                sodiumMg: entry.sodiumMg * scale,
                nutrients: entry.nutrients.scaled(by: scale),
                category: entry.category,
                date: entry.date,
                aiGenerated: entry.aiGenerated,
                // Totals scaled by s = s× the portions too — keep the
                // phone's per-portion basis intact for its edit sheet.
                quantity: entry.quantity * scale
            )
            do {
                try await health.deleteFoodEntry(id: entry.id)
            } catch {
                // Roll the replacement back (the phone edit's rule):
                // leaving it alongside the original double-counts the
                // meal in every total.
                try? await health.deleteFoodEntry(id: newId)
                throw error
            }
            WKInterfaceDevice.current().play(.success)
            showFlash("✓ \(entry.name) updated", isError: false)
            await refresh()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash(Self.writeFailureFlash(error, verb: "save"), isError: true)
            await refresh()
            return false
        }
    }

    /// Health-access blame is wrong (and misleading) when the entry
    /// simply belongs to another app — say which it is.
    private static func writeFailureFlash(_ error: Error, verb: String) -> String {
        HealthKitService.isForeignObjectError(error)
            ? "Another app logged this — remove it in Health"
            : "Couldn't \(verb) — check Health access"
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
            showFlash(Self.writeFailureFlash(error, verb: "remove"), isError: true)
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
        // Spoken too: the transient text + haptic left VoiceOver users
        // unable to tell a failed log from a success (the model's own
        // comment about ambiguous haptics, one layer up).
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: .seconds(isError ? 4 : 2))
            if generation == flashGeneration { flash = nil }
        }
    }
}
