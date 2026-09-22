import Testing
import Foundation
import SwiftData
@testable import OnigiriKit

/// `Meal.items` needs an explicit inverse for the same reason
/// `Food.mealItems` got one: deleting an item a meal still references
/// otherwise leaves a dangling reference that traps the process on the
/// next `items` access.
@MainActor
struct MealItemsInverseTests {
    /// Keep the container alive for the test's duration — returning only a
    /// context lets the container deallocate and SwiftData traps on use.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
    }

    @Test func linkingItemsSetsTheInverse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = Food(name: "Rice", kcal: 200, sodiumMg: 0)
        context.insert(food)
        let meal = Meal(name: "Bowl", items: [MealItem(food: food)])
        context.insert(meal)
        try context.save()

        #expect(meal.items.count == 1)
        #expect(meal.items.first?.meal === meal)
    }

    /// The crash-class scenario: delete an item WITHOUT detaching it from
    /// the meal first. With the inverse, SwiftData unlinks it; without,
    /// the next `meal.items` access kills the process.
    @Test func deletingAnItemDirectlyDetachesItFromTheMeal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let rice = Food(name: "Rice", kcal: 200, sodiumMg: 0)
        let egg = Food(name: "Egg", kcal: 70, sodiumMg: 65)
        context.insert(rice)
        context.insert(egg)
        let meal = Meal(name: "Bowl", items: [
            MealItem(food: rice), MealItem(food: egg),
        ])
        context.insert(meal)
        try context.save()

        let doomed = try #require(meal.items.first { $0.food?.name == "Egg" })
        context.delete(doomed)
        try context.save()

        #expect(meal.items.count == 1)
        #expect(meal.totalKcal == 200)
    }

    /// The meal editor's replace pattern: unlink by reassigning `items`,
    /// THEN delete the old items (the reverse order is the landmine).
    @Test func replacingItemsUnlinksBeforeDeleting() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let rice = Food(name: "Rice", kcal: 200, sodiumMg: 0)
        let tofu = Food(name: "Tofu", kcal: 90, sodiumMg: 10)
        context.insert(rice)
        context.insert(tofu)
        let meal = Meal(name: "Bowl", items: [MealItem(food: rice)])
        context.insert(meal)
        try context.save()

        let oldItems = meal.items
        meal.items = [MealItem(food: tofu, quantity: 2)]
        oldItems.forEach(context.delete)
        try context.save()

        #expect(meal.items.count == 1)
        #expect(meal.totalKcal == 180)
        #expect(meal.items.first?.meal === meal)
    }
}
