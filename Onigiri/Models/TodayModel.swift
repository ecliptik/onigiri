import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var foodLog: [FoodLogEntry] = []
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
        await refresh()
    }

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
            async let weight = health.latestBodyMassLb()
            async let averageBurn = health.averageDailyBurnKcal()
            let (loadedSummary, loadedLog, loadedWeight, loadedBurn) =
                try await (summary, foodLog, weight, averageBurn)
            guard generation == refreshGeneration else { return }
            self.summary = loadedSummary
            self.foodLog = loadedLog
            self.currentWeightLb = loadedWeight
            self.averageBurnKcal = loadedBurn
            errorMessage = nil
            print("[onigiri] refresh: intake=\(self.summary.intakeKcal) burn=\(self.summary.totalBurnKcal) log=\(self.foodLog.count) weight=\(String(describing: self.currentWeightLb)) avgBurn=\(String(describing: self.averageBurnKcal))")
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = "Couldn't read Health data: \(error.localizedDescription)"
            print("[onigiri] refresh FAILED: \(error)")
        }
    }
}
