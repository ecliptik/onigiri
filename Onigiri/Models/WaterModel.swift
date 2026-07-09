import Foundation
import OnigiriKit

@Observable
final class WaterModel {
    private(set) var entries: [WaterLogEntry] = []
    private(set) var errorMessage: String?

    private let health = HealthKitService()

    var totalOz: Double { entries.reduce(0) { $0 + $1.oz } }

    func refresh() async {
        do {
            entries = try await health.todayWaterEntries()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't read water data: \(error.localizedDescription)"
        }
    }

    func add(oz: Double) async {
        do {
            try await health.logWater(oz: oz)
            await refresh()
        } catch {
            errorMessage = "Couldn't log water: \(error.localizedDescription)"
        }
    }

    func delete(_ entry: WaterLogEntry) async {
        do {
            try await health.deleteWaterEntry(id: entry.id)
            await refresh()
        } catch {
            errorMessage = "Couldn't delete that entry — Onigiri can only remove water it logged itself."
        }
    }
}
