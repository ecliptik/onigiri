import Testing
import Foundation
import SwiftData
import CoreData
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

    /// End-to-end reproduction of the on-device crash loop: a food row
    /// deleted out from under a meal item (batch deletes skip relationship
    /// processing, exactly like pre-inverse stores), then the Core Data
    /// pre-flight repair, then a normal SwiftData open that computes meal
    /// totals — which used to trap the process.
    @Test func storeRepairHealsAPoisonedStoreOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Poisoned.sqlite")

        // Seed a normal library.
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Food.self, Meal.self, GoalSettings.self,
                configurations: config
            )
            let context = container.mainContext
            let ghost = Food(name: "Ghost", kcal: 100, sodiumMg: 5)
            let keeper = Food(name: "Oats", kcal: 150, sodiumMg: 2)
            context.insert(ghost)
            context.insert(keeper)
            context.insert(Meal(name: "Breakfast", items: [
                MealItem(food: ghost), MealItem(food: keeper),
            ]))
            try context.save()
        }

        // Poison it: delete the food row without relationship processing.
        do {
            let model = try #require(NSManagedObjectModel.makeManagedObjectModel(
                for: [Food.self, Meal.self, MealItem.self, GoalSettings.self]
            ))
            let container = NSPersistentContainer(name: "Poisoned", managedObjectModel: model)
            let description = NSPersistentStoreDescription(url: url)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in #expect(error == nil) }
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Food")
            fetch.predicate = NSPredicate(format: "name == %@", "Ghost")
            try container.viewContext.execute(NSBatchDeleteRequest(fetchRequest: fetch))
            let coordinator = container.persistentStoreCoordinator
            try coordinator.persistentStores.forEach { try coordinator.remove($0) }
        }

        LibraryMaintenance.repairStore(at: url)

        // The store must now open and compute totals without trapping.
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
        let meals = try container.mainContext.fetch(FetchDescriptor<Meal>())
        let meal = try #require(meals.first)
        #expect(meal.items.count == 1)
        #expect(meal.totalKcal == 150)
    }
}
