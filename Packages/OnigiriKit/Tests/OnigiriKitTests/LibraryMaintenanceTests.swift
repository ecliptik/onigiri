import Testing
import Foundation
import SwiftData
@testable import OnigiriKit

@MainActor
struct LibraryMaintenanceTests {
    /// Keep the container alive for the test's duration — returning only a
    /// context lets the container deallocate and SwiftData traps on use.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
    }

    /// Deleting a food must not leave meal items pointing at it — the
    /// device crash-looped on exactly that (SwiftData traps on the next
    /// property access of an invalidated model). Note: with the inverse
    /// relationship, foods must be inserted before MealItem(food:) links
    /// to them, matching how the app builds meals.
    @Test func deletingAFoodNullifiesItsMealItems() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = Food(name: "Blueberries", kcal: 85, sodiumMg: 1)
        let keeper = Food(name: "Oats", kcal: 150, sodiumMg: 2)
        context.insert(food)
        context.insert(keeper)
        let meal = Meal(name: "Breakfast", items: [
            MealItem(food: food), MealItem(food: keeper),
        ])
        context.insert(meal)
        try context.save()

        context.delete(food)
        try context.save()

        #expect(meal.items.allSatisfy { $0.food?.name != "Blueberries" })
        #expect(meal.totalKcal == 150)
    }

    @Test func repairDropsFoodlessItemsAndKeepsTheRest() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = Food(name: "Toast", kcal: 120, sodiumMg: 180)
        context.insert(food)
        let meal = Meal(name: "Snack", items: [
            MealItem(food: food), MealItem(food: food),
        ])
        context.insert(meal)
        try context.save()
        // Simulate the pre-inverse leftovers: an item whose food is gone.
        meal.items[1].food = nil
        try context.save()

        LibraryMaintenance.repairDanglingFoodReferences(context: context)

        #expect(meal.items.count == 1)
        #expect(meal.totalKcal == 120)
    }
}
