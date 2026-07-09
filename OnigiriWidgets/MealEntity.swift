import AppIntents
import SwiftData
import OnigiriKit

/// A saved meal, exposed to widget configuration ("Edit Widget" → pick meal).
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
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MealEntity] {
        try allMeals().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MealEntity] {
        try allMeals()
    }

    @MainActor
    private func allMeals() throws -> [MealEntity] {
        let container = try SharedStore.modelContainer()
        let meals = try container.mainContext.fetch(
            FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.name)])
        )
        return meals.map {
            MealEntity(id: $0.uuid.uuidString, name: $0.name, kcal: $0.totalKcal)
        }
    }
}
