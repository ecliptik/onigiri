import Foundation
import WidgetKit
import OnigiriKit

@Observable
final class WaterModel {
    private(set) var entries: [WaterLogEntry] = []
    private(set) var errorMessage: String?
    private(set) var selectedDate = Calendar.current.startOfDay(for: .now)

    private let health = HealthKitService()
    /// Same stale-refresh guard as TodayModel: only the newest publishes.
    private var refreshGeneration = 0

    var totalOz: Double { entries.reduce(0) { $0 + $1.oz } }
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

    func refresh() async {
        if isToday {
            selectedDate = Calendar.current.startOfDay(for: .now)
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            let loaded = try await health.waterEntries(on: selectedDate)
            guard generation == refreshGeneration else { return }
            entries = loaded
            errorMessage = nil
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = "Couldn't read water data: \(error.localizedDescription)"
        }
    }

    @MainActor
    func add(oz: Double) async {
        // Shared feedback (toast + undo + haptic + widget reload); logs
        // into the browsed day so past days can be backfilled.
        await LogActions.logWater(oz: oz, date: DayBounds.logTimestamp(for: selectedDate))
        await refresh()
    }

    @MainActor
    func delete(_ entry: WaterLogEntry) async {
        await LogActions.deleteWaterEntry(entry)
        await refresh()
    }
}
