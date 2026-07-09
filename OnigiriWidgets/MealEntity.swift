import AppIntents
import OnigiriKit

/// A saved meal, exposed to widget configuration ("Edit Widget" → pick meal).
/// Reads the lightweight mirror in the App Group defaults — the widget
/// process is memory-capped, so no SwiftData here.
struct MealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
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
        allMeals().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MealEntity] {
        allMeals()
    }

    private func allMeals() -> [MealEntity] {
        WatchSync.loadMeals().map {
            MealEntity(id: $0.id.uuidString, name: $0.name, kcal: $0.kcal)
        }
    }
}
