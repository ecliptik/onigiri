import Testing
import Foundation
import SwiftData
@testable import OnigiriKit

/// The Settings "Reset" section's wipe must leave an empty, consistent
/// store. Pinned here because the first implementation used
/// `delete(model:)` batch deletes, which bypass relationship
/// maintenance and die on the mandatory MealItem/food nullify inverse —
/// the reset round-trip E2E caught it failing silently.
@MainActor
struct LibraryWipeTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
    }

    @Test func batchWipeEmptiesTheStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let rice = Food(name: "Rice", kcal: 200, sodiumMg: 0)
        let egg = Food(name: "Egg", kcal: 70, sodiumMg: 65)
        context.insert(rice)
        context.insert(egg)
        context.insert(Meal(name: "Bowl", items: [
            MealItem(food: rice), MealItem(food: egg),
        ]))
        context.insert(GoalSettings(targetWeightLb: 190, targetDate: .now))
        try context.save()

        try LibraryMaintenance.wipeLibrary(context: context)
        try LibraryMaintenance.wipeGoals(context: context)

        #expect(try context.fetchCount(FetchDescriptor<Food>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Meal>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MealItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalSettings>()) == 0)
    }
}
