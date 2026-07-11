import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var foodLog: [FoodLogEntry] = []
    private(set) var waterLog: [WaterLogEntry] = []
    private(set) var currentWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    private(set) var errorMessage: String?
    private(set) var selectedDate = Calendar.current.startOfDay(for: .now)

    private let health = HealthKitService()
    private var started = false
    /// Refreshes fire concurrently (task/appear/foreground/day swipes); only
    /// the newest may publish, or a slow old day overwrites the current one.
    private var refreshGeneration = 0

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    func goToPreviousDay() async {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = previous
        await refresh()
    }

    func goToNextDay() async {
        guard !isToday,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        selectedDate = min(next, Calendar.current.startOfDay(for: .now))
        await refresh()
    }

    /// Jump straight to a day (date picker, Calendar's "View day").
    func select(day: Date) async {
        selectedDate = min(
            Calendar.current.startOfDay(for: day),
            Calendar.current.startOfDay(for: .now)
        )
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
    }

    /// Day data only — fast enough that browsing feels immediate.
    func refresh() async {
        // A new calendar day rolls the view back to "today".
        if isToday {
            selectedDate = Calendar.current.startOfDay(for: .now)
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            async let summary = health.daySummary(for: selectedDate)
            async let foodLog = health.foodEntries(on: selectedDate)
            async let waterLog = health.waterEntries(on: selectedDate)
            let (loadedSummary, loadedFood, loadedWater) =
                try await (summary, foodLog, waterLog)
            guard generation == refreshGeneration else { return }
            self.summary = loadedSummary
            self.foodLog = loadedFood
            self.waterLog = loadedWater
        } catch {
            guard generation == refreshGeneration else { return }
            // Transient read failures toast like every other transient
            // failure; errorMessage stays for the persistent start()
            // states (Health unavailable, authorization failed).
            ToastCenter.shared.show("Couldn't read Health data: \(error.localizedDescription)")
            print("[onigiri] refresh FAILED: \(error)")
        }
    }
}
