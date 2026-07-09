import AppIntents
import OnigiriKit
import os

// Logger is thread-safe; opt out of the target's MainActor default.
private nonisolated(unsafe) let configLog = Logger(subsystem: "com.ecliptik.Onigiri.widgets", category: "config")

/// A saved meal, exposed to widget configuration ("Edit Widget" → pick meal).
/// Reads the lightweight mirror in the App Group defaults — the widget
/// process is memory-capped, so no SwiftData here.
struct MealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Meal"
    static let defaultQuery = MealEntityQuery()

    var id: String
    var name: String
    var kcal: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(Int(kcal)) kcal"
        )
    }
}

struct MealEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MealEntity] {
        let meals = allMeals()
        configLog.info("entities(for: \(identifiers.count)) -> \(meals.count) meals in mirror")
        return meals.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MealEntity] {
        let meals = allMeals()
        configLog.info("suggestedEntities -> \(meals.count) meals in mirror")
        return meals
    }

    private func allMeals() -> [MealEntity] {
        WatchSync.loadMeals().map {
            MealEntity(id: $0.id.uuidString, name: $0.name, kcal: $0.kcal)
        }
    }
}
