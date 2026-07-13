import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var foodLog: [FoodLogEntry] = []
    private(set) var waterLog: [WaterLogEntry] = []
    /// Day totals for the two configurable tracked-metric slots, in each
    /// nutrient's label unit (sodium/water reuse the summary's numbers).
    private(set) var trackedTotals: [Double] = [0, 0]
    private(set) var currentWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    private(set) var errorMessage: String?
    /// Health write access explicitly denied — every log would fail
    /// with an opaque toast, so Today shows a recovery hint instead.
    private(set) var healthWriteDenied = false
    private(set) var selectedDate = Calendar.current.startOfDay(for: .now)

    private let health = HealthKitService()
    private var started = false
    /// Refreshes fire concurrently (task/appear/foreground/day swipes); only
    /// the newest may publish, or a slow old day overwrites the current one.
    private var refreshGeneration = 0

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Tracks intent, not the date: once midnight passes, `isToday` is
    /// already false for the day the user was pinned to, so only this
    /// flag can tell "left on today overnight" (roll forward) apart from
    /// "deliberately browsing yesterday" (stay put).
    private var followsToday = true

    func goToPreviousDay() async {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = previous
        followsToday = false
        await refresh()
    }

    func goToNextDay() async {
        guard !isToday,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        selectedDate = min(next, Calendar.current.startOfDay(for: .now))
        followsToday = isToday
        await refresh()
    }

    /// Jump straight to a day (date picker, Calendar's "View day").
    func select(day: Date) async {
        selectedDate = min(
            Calendar.current.startOfDay(for: day),
            Calendar.current.startOfDay(for: .now)
        )
        followsToday = isToday
        await refresh()
    }

    /// Expected full-day burn: 14-day average when history exists, otherwise
    /// today's accrual or a conservative floor.
    var expectedDailyBurnKcal: Double {
        averageBurnKcal ?? max(summary.totalBurnKcal, 2000)
    }

    /// One-time startup: prompt for HealthKit access if never asked, then load.
    /// The view's .task can re-fire on tab switches — only run once.
    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        guard HealthKitService.isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        var seeding = false
        #if DEBUG
        seeding = ProcessInfo.processInfo.arguments.contains("--seed-sample-data")
        #endif
        do {
            #if DEBUG
            if seeding {
                // One combined sheet covering the seeder's extra types too.
                try await health.requestDebugSeedAuthorization()
            }
            #endif
            if !seeding, try await health.shouldRequestAuthorization() {
                try await health.requestAuthorization()
            }
        } catch {
            errorMessage = "Health authorization failed: \(error.localizedDescription)"
        }
        #if DEBUG
        if seeding {
            do {
                try await health.seedSampleData()
                print("[onigiri] seed: saved OK")
            } catch {
                errorMessage = "Seeding failed: \(error.localizedDescription)"
                print("[onigiri] seed FAILED: \(error)")
            }
        }
        #endif
        await loadStatic()
        await refresh()
    }

    /// Weight and average burn don't depend on the browsed day — loading
    /// them per chevron tap made day switching feel laggy. Fetched on
    /// start and on foregrounding instead.
    func loadStatic() async {
        currentWeightLb = (try? await health.latestBodyMassLb()) ?? currentWeightLb
        averageBurnKcal = (try? await health.averageDailyBurnKcal()) ?? averageBurnKcal
        // Re-checked on every foreground: the user may have just flipped
        // access in the Health app.
        healthWriteDenied = health.sharingDenied()
    }

    /// Day data only — fast enough that browsing feels immediate.
    func refresh() async {
        // A new calendar day rolls the view forward to the new "today" —
        // unless the user deliberately navigated to a past day.
        if followsToday {
            selectedDate = Calendar.current.startOfDay(for: .now)
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            async let summary = health.daySummary(for: selectedDate)
            async let foodLog = health.foodEntries(on: selectedDate)
            async let waterLog = health.waterEntries(on: selectedDate)
            async let tracked1 = trackedTotal(slot: 1)
            async let tracked2 = trackedTotal(slot: 2)
            let (loadedSummary, loadedFood, loadedWater, loaded1, loaded2) =
                try await (summary, foodLog, waterLog, tracked1, tracked2)
            guard generation == refreshGeneration else { return }
            self.summary = loadedSummary
            self.foodLog = loadedFood
            self.waterLog = loadedWater
            // Sodium/water ride the summary — no second query, and the
            // numbers can't disagree with the rest of the screen.
            self.trackedTotals = [
                loaded1 ?? slotSummaryValue(slot: 1, from: loadedSummary),
                loaded2 ?? slotSummaryValue(slot: 2, from: loadedSummary),
            ]
        } catch {
            guard generation == refreshGeneration else { return }
            // Transient read failures toast like every other transient
            // failure; errorMessage stays for the persistent start()
            // states (Health unavailable, authorization failed).
            ToastCenter.shared.show("Couldn't read Health data: \(error.localizedDescription)")
            print("[onigiri] refresh FAILED: \(error)")
        }
    }

    /// Nil for sodium/water — the caller reuses the day summary's values.
    private func trackedTotal(slot: Int) async throws -> Double? {
        switch SharedStore.trackedNutrient(slot: slot) {
        case nil: return 0 // slot is off — nothing to fetch
        case .sodium?, .water?: return nil
        case .some(let nutrient): return try await health.dayTotal(of: nutrient, for: selectedDate)
        }
    }

    private func slotSummaryValue(slot: Int, from summary: DailyEnergySummary) -> Double {
        switch SharedStore.trackedNutrient(slot: slot) {
        case .sodium?: summary.sodiumMg
        case .water?: summary.waterOz
        default: 0
        }
    }
}
