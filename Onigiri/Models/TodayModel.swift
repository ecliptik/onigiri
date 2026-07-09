import Foundation
import OnigiriKit

@Observable
final class TodayModel {
    private(set) var summary: DailyEnergySummary = .zero
    private(set) var errorMessage: String?
    private(set) var isLoaded = false

    private let health = HealthKitService()

    /// One-time startup: prompt for HealthKit access if never asked, then load.
    func start() async {
        guard HealthKitService.isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        do {
            if try await health.shouldRequestAuthorization() {
                try await health.requestAuthorization()
            }
        } catch {
            errorMessage = "Health authorization failed: \(error.localizedDescription)"
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
            await seedSampleData()
            return
        }
        #endif
        await refresh()
    }

    func refresh() async {
        do {
            summary = try await health.todaySummary()
            errorMessage = nil
            isLoaded = true
        } catch {
            errorMessage = "Couldn't read Health data: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func seedSampleData() async {
        do {
            try await health.seedSampleData()
            await refresh()
        } catch {
            errorMessage = "Seeding failed: \(error.localizedDescription)"
        }
    }
    #endif
}
