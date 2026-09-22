import Testing
import Foundation
import SwiftData
@testable import OnigiriKit

/// Behind the "It will also be removed from …" delete confirmation.
/// Untested while it lived in `FoodsView` (audit, 2026-08-17), and a
/// wrong answer degrades to a warning that is quietly incorrect rather
/// than to a crash — so nothing else would ever catch it.
@MainActor
struct LibraryReferencesTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func namesTheMealsHoldingTheDoomedFood() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oats = Food(name: "Oats", kcal: 150, sodiumMg: 2)
        let milk = Food(name: "Milk", kcal: 90, sodiumMg: 40)
        context.insert(oats)
        context.insert(milk)
        context.insert(Meal(name: "Porridge", items: [MealItem(food: oats), MealItem(food: milk)]))
        context.insert(Meal(name: "Cereal", items: [MealItem(food: milk)]))
        context.insert(Meal(name: "Toast plate", items: [MealItem(food: oats)]))
        try context.save()

        let meals = try context.fetch(FetchDescriptor<Meal>())
        let names = LibraryReferences.mealNames(
            referencing: [oats.persistentModelID], in: meals
        )
        // Sorted and unique, ready to read out in a sentence.
        #expect(names == ["Porridge", "Toast plate"])
    }

    @Test func aFoodNoMealUsesNamesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oats = Food(name: "Oats", kcal: 150, sodiumMg: 2)
        let lonely = Food(name: "Anchovies", kcal: 60, sodiumMg: 900)
        context.insert(oats)
        context.insert(lonely)
        context.insert(Meal(name: "Porridge", items: [MealItem(food: oats)]))
        try context.save()

        let meals = try context.fetch(FetchDescriptor<Meal>())
        #expect(LibraryReferences.mealNames(
            referencing: [lonely.persistentModelID], in: meals
        ).isEmpty)
    }

    /// Deleting several foods at once names each meal ONCE, however many
    /// of the doomed foods it happens to contain.
    @Test func aMealHoldingTwoDoomedFoodsIsNamedOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oats = Food(name: "Oats", kcal: 150, sodiumMg: 2)
        let milk = Food(name: "Milk", kcal: 90, sodiumMg: 40)
        context.insert(oats)
        context.insert(milk)
        context.insert(Meal(name: "Porridge", items: [MealItem(food: oats), MealItem(food: milk)]))
        try context.save()

        let meals = try context.fetch(FetchDescriptor<Meal>())
        let names = LibraryReferences.mealNames(
            referencing: [oats.persistentModelID, milk.persistentModelID], in: meals
        )
        #expect(names == ["Porridge"])
    }

    /// An item whose food is already nil references no food to lose, so
    /// its meal must not be named on the strength of it.
    @Test func aFoodlessItemDoesNotImplicateItsMeal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oats = Food(name: "Oats", kcal: 150, sodiumMg: 2)
        let doomed = Food(name: "Doomed", kcal: 100, sodiumMg: 5)
        context.insert(oats)
        context.insert(doomed)
        let meal = Meal(name: "Porridge", items: [MealItem(food: oats), MealItem(food: doomed)])
        context.insert(meal)
        try context.save()
        // Found by NAME, not by index. A SwiftData to-many comes back
        // unordered, so `items[1]` nils whichever item happened to sort
        // there — half the time that was the oats, leaving the doomed
        // food still referenced and the meal correctly named, which read
        // as a failure. Flaky the day it was written (2026-08-17); it
        // passed the first several runs.
        let doomedItem = try #require(meal.items.first { $0.food?.name == "Doomed" })
        doomedItem.food = nil
        try context.save()

        let meals = try context.fetch(FetchDescriptor<Meal>())
        #expect(LibraryReferences.mealNames(
            referencing: [doomed.persistentModelID], in: meals
        ).isEmpty)
    }
}

/// The library list order, which Foods and the Log sheet had each
/// spelled out for themselves.
struct LibraryOrderTests {
    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func recencyLeadsWhenSortingByRecent() {
        #expect(LibrarySearch.isOrderedBefore(
            (newer, "Zucchini"), (older, "Apple"), byRecency: true
        ))
    }

    @Test func nameLeadsWhenSortingByName() {
        #expect(LibrarySearch.isOrderedBefore(
            (older, "Apple"), (newer, "Zucchini"), byRecency: false
        ))
    }

    /// Alphabetical is the tie-break in BOTH modes — two rows logged in
    /// the same instant must not order arbitrarily.
    @Test func equalRecencyFallsBackToTheName() {
        #expect(LibrarySearch.isOrderedBefore(
            (newer, "Apple"), (newer, "Zucchini"), byRecency: true
        ))
        #expect(!LibrarySearch.isOrderedBefore(
            (newer, "Zucchini"), (newer, "Apple"), byRecency: true
        ))
    }

    @Test func theNameTieBreakIgnoresCase() {
        #expect(LibrarySearch.isOrderedBefore(
            (newer, "apple"), (newer, "Banana"), byRecency: true
        ))
    }
}
