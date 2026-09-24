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

    /// Injectable so `OnigiriWatchTests` can drive the model against a
    /// fake instead of real HealthKit (`WatchHealthWriting`).
    private let health: WatchHealthWriting
    private var started = false
    /// Double-taps on a slow HealthKit write must not log twice.
    private var isLogging = false
    /// Completed-refresh gate: page swipes and re-activations fired a
    /// full plan load each (TabView pre-renders neighbors, so one open
    /// plus a swipe could run it 3-4×).
    private var refreshGate = RefreshGate()
    /// The refresh currently underway, so passive callers can join it —
    /// at launch, start()'s refresh plus the pre-rendered pages' onAppear
    /// used to run three concurrent full query sets before the first
    /// completion could mark the refresh gate.
    private var refreshTask: Task<Void, Never>?

    /// Transient line under the buttons: haptics alone made a failed
    /// log indistinguishable from a successful one.
    private(set) var flash: String?
    private(set) var flashIsError = false
    /// Tap-to-undo riding the flash — set only by `deleteEntry`, whose
    /// no-confirm swipe otherwise had no way back (the phone's Undo
    /// toast rule; audit, 2026-08-17). The render sites turn the flash
    /// into a Button while this is non-nil.
    private(set) var flashUndo: (() -> Void)?
    private var flashGeneration = 0
    /// Write access denied — zeros forever otherwise, with no hint.
    private(set) var healthDenied = false

    var waterServingOz: Double { SharedStore.waterServingOz }
    var waterGoalOz: Double { SharedStore.waterGoalOz }

    init(health: WatchHealthWriting = HealthKitService()) {
        self.health = health
    }

    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        #if DEBUG
        // Before ANY load — the phone's rule, same reason.
        if TodayBurnFloor.clearTodayIfRequested() {
            print("[onigiri-watch] cleared today's burn floor")
        }
        #endif
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
            _ = try? await health.logFood(
                name: "Avocado toast", kcal: 420, sodiumMg: 620, nutrients: NutrientValues(),
                category: .breakfast, date: .now, aiGenerated: false, quantity: 1, mealItems: [])
            _ = try? await health.logFood(
                name: "Chicken bowl", kcal: 610, sodiumMg: 880, nutrients: NutrientValues(),
                category: .lunch, date: .now, aiGenerated: false, quantity: 1, mealItems: [])
            _ = try? await health.logFood(
                name: "Trail mix", kcal: 205, sodiumMg: 120, nutrients: NutrientValues(),
                category: .snack, date: .now, aiGenerated: false, quantity: 1, mealItems: [])
            _ = try? await health.logWater(oz: 24, date: .now)
            await refresh()
            return
        }
        #endif
        if (try? await health.shouldRequestAuthorization()) == true {
            try? await health.requestAuthorization()
        }
        await refresh()
        #if DEBUG
        await printDiagnostics()
        #endif
    }

    #if DEBUG
    /// The wrist-side twin of TodayModel's launch diagnostics, once per
    /// launch.
    ///
    /// Exists because a phone/watch disagreement could not be MEASURED
    /// from the watch (2026-09-20: "left" on the phone against "over"
    /// on the wrist). Both devices run the same
    /// arithmetic, but every input to it is per-device — intake and both
    /// burn channels come from THIS store, `TodayBurnFloor` keeps its own
    /// day mark here, and the weight the deficit rides may be the phone's
    /// synced basis or this store's own (`resolvedWeight`). With
    /// `DailyPlanLoader.diagnose` running on the phone alone, only one
    /// side of the gap could ever be read, which makes attributing it to
    /// a term guesswork.
    ///
    /// It goes to `DebugDiagnosticsLog`, not just the console: `print()`
    /// never reaches an agent shell (see that type), and a live console
    /// is the wrong instrument anyway — the gap has to be caught while
    /// it is on screen, and the file can be pulled afterwards. The
    /// console lines stay for a run under Xcode, prefixed distinctly
    /// from the phone's `[onigiri]` so one capture of both is readable.
    private func printDiagnostics() async {
        var lines: [String] = []
        // Today, plus yesterday: a gap looked at in the morning may
        // belong to the day that just rolled over.
        for offset in [0, -1] {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            // A DEBUG probe, kept off the test seam: only the real
            // service has it, and a fake has nothing to diagnose.
            guard let service = health as? HealthKitService else { continue }
            lines.append("day\(offset) \(await service.diagnoseIntake(for: day))")
        }
        // `sync.goal`, not `WatchSync.loadGoal()`: this is the goal the
        // headline actually rendered, including a push applied since
        // launch — and a stale goal here is itself one of the answers.
        lines.append(await DailyPlanLoader.diagnose(
            goal: sync.goal, burnCorrectionKcal: SharedStore.burnCorrectionKcal))
        // This watch's OWN journals, not the phone's: they live in each
        // device's App Group, which is exactly why they are worth having
        // from both sides.
        lines.append(contentsOf: WidgetBurnGate.planJournal().map { "plan \($0)" })
        lines.append(contentsOf: WidgetBurnGate.journal().map { "burn \($0)" })
        for line in lines { print("[onigiri-watch] \(line)") }
        DebugDiagnosticsLog.append(lines.map { "watch \($0)" })
    }
    #endif

    /// Passive entry point (page onAppear, scene re-activation): join a
    /// refresh already underway, and skip the query set when fresh —
    /// unless the day rolled over. Logs and start() still call refresh()
    /// directly (post-write data must never piggyback on a pre-write read).
    func refreshIfStale(maxAge: TimeInterval = 30) async {
        if let running = refreshTask {
            await running.value
            return
        }
        guard refreshGate.isStale(maxAge: maxAge) else { return }
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
        async let planRead = DailyPlanLoader.load(
            goal: sync.goal, burnCorrectionKcal: SharedStore.burnCorrectionKcal)
        async let entriesRead = health.todayFoodEntries(now: .now)
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
            refreshGate.markRefreshed()
        }
    }

    private func slotTotal(slot: Int) async -> Double {
        guard let nutrient = SharedStore.trackedNutrient(slot: slot) else { return 0 }
        return (try? await health.dayTotal(of: nutrient, for: .now, now: .now)) ?? 0
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
                quantity: entry.quantity * scale,
                // Unscaled, as on the phone: a meal's items are that same
                // per-portion basis, and dropping them turned a resized
                // meal into a plain food.
                mealItems: entry.mealItems
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
            sync.notifyPhoneOfLog()
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
            // No confirmation, BECAUSE undo: the phone deletes the same
            // way (LogActions.deleteFoodEntry — "an accidental swipe
            // costs one tap"), and the watch had shipped the no-confirm
            // half without the way back — a fat-fingered swipe on a
            // 41 mm screen permanently deleted a HealthKit sample
            // (audit, 2026-08-17). The captured entry re-logs whole,
            // meal composition included.
            showFlash("Removed \(entry.name)", isError: false) { [weak self] in
                Task { await self?.undoDelete(entry) }
            }
            sync.notifyPhoneOfLog()
            await refresh()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash(Self.writeFailureFlash(error, verb: "remove"), isError: true)
            return false
        }
    }

    /// Re-log the captured entry — the flash's tap-to-undo.
    private func undoDelete(_ entry: FoodLogEntry) async {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }
        flashUndo = nil
        do {
            _ = try await health.logFood(
                name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                nutrients: entry.nutrients, category: entry.category,
                date: entry.date, aiGenerated: entry.aiGenerated,
                quantity: entry.quantity, mealItems: entry.mealItems
            )
            WKInterfaceDevice.current().play(.success)
            showFlash("Restored \(entry.name) ✓", isError: false)
            sync.notifyPhoneOfLog()
            await refresh()
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash(Self.writeFailureFlash(error, verb: "restore"), isError: true)
        }
    }

    @discardableResult
    func logWater() async -> Bool {
        guard !isLogging else { return false }
        isLogging = true
        defer { isLogging = false }
        do {
            try await health.logWater(oz: waterServingOz, date: .now)
            WKInterfaceDevice.current().play(.success)
            showFlash(
                "+\(SharedStore.waterUnit.text(fromOz: waterServingOz)) ✓",
                isError: false
            )
            sync.notifyPhoneOfLog()
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
            // Carry the meal's slot, nutrients, and composition like the
            // phone does; old payloads without them fall back to
            // time-of-day inference (and no breakdown).
            try await health.logFood(
                name: meal.name, kcal: meal.kcal, sodiumMg: meal.sodiumMg,
                nutrients: meal.nutrients ?? NutrientValues(),
                category: meal.category.flatMap(FoodCategory.init(rawValue:)),
                date: .now, aiGenerated: false, quantity: 1,
                mealItems: meal.items ?? []
            )
            WKInterfaceDevice.current().play(.success)
            showFlash("✓ \(meal.name)", isError: false)
            sync.notifyPhoneOfLog()
            await refresh()
            return true
        } catch {
            WKInterfaceDevice.current().play(.failure)
            showFlash("Couldn't log — check Health access", isError: true)
            return false
        }
    }

    private func showFlash(_ message: String, isError: Bool, undo: (() -> Void)? = nil) {
        flashGeneration += 1
        let generation = flashGeneration
        flash = message
        flashIsError = isError
        flashUndo = undo
        // Spoken too: the transient text + haptic left VoiceOver users
        // unable to tell a failed log from a success (the model's own
        // comment about ambiguous haptics, one layer up).
        AccessibilityNotification.Announcement(
            undo == nil ? message : "\(message). Undo available."
        ).post()
        Task {
            // An undo-carrying flash lingers longer: it IS the recovery
            // affordance (the phone toast holds five seconds for the
            // same reason).
            try? await Task.sleep(for: .seconds(isError ? 4 : (undo == nil ? 2 : 6)))
            if generation == flashGeneration {
                flash = nil
                flashUndo = nil
            }
        }
    }
}
