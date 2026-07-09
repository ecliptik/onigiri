import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var foodLog: [FoodLogEntry] = []
    private(set) var currentWeightLb: Double?
    private(set) var averageBurnKcal: Double?
    private(set) var errorMessage: String?

    private let health = HealthKitService()
    private var started = false

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
        do {
            async let summary = health.todaySummary()
            async let foodLog = health.todayFoodEntries()
            async let weight = health.latestBodyMassLb()
            async let averageBurn = health.averageDailyBurnKcal()
            self.summary = try await summary
            self.foodLog = try await foodLog
            self.currentWeightLb = try await weight
            self.averageBurnKcal = try await averageBurn
            errorMessage = nil
            print("[onigiri] refresh: intake=\(self.summary.intakeKcal) burn=\(self.summary.totalBurnKcal) log=\(self.foodLog.count) weight=\(String(describing: self.currentWeightLb)) avgBurn=\(String(describing: self.averageBurnKcal))")
        } catch {
            errorMessage = "Couldn't read Health data: \(error.localizedDescription)"
            print("[onigiri] refresh FAILED: \(error)")
        }
    }

    func delete(_ entry: FoodLogEntry) async {
        do {
            try await health.deleteFoodEntry(id: entry.id)
            await refresh()
        } catch {
            errorMessage = "Couldn't delete entry: \(error.localizedDescription)"
        }
    }
}
