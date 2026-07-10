import Foundation
import WidgetKit
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

    @MainActor
    func add(oz: Double) async {
        // Shared feedback (toast + undo + haptic + widget reload).
        await LogActions.logWater(oz: oz)
        await refresh()
    }

    @MainActor
    func delete(_ entry: WaterLogEntry) async {
        await LogActions.deleteWaterEntry(entry)
        await refresh()
    }
}
