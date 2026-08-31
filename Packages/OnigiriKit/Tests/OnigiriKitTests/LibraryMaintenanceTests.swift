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

        let succeeded = LibraryMaintenance.repairStore(at: url)
        #expect(succeeded, "a repair that actually ran and fixed the store must report success")

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

    /// The repair must be inert on a healthy store: a pass that "fixes"
    /// intact data is worse than one that never runs.
    @Test func storeRepairLeavesAHealthyStoreAlone() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Healthy.sqlite")

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Food.self, Meal.self, GoalSettings.self,
                configurations: config
            )
            let context = container.mainContext
            let oats = Food(name: "Oats", kcal: 150, sodiumMg: 2)
            let milk = Food(name: "Milk", kcal: 90, sodiumMg: 40)
            context.insert(oats)
            context.insert(milk)
            context.insert(Meal(name: "Breakfast", items: [
                MealItem(food: oats), MealItem(food: milk),
            ]))
            try context.save()
        }

        let succeeded = LibraryMaintenance.repairStore(at: url)
        #expect(succeeded, "a no-op repair on a healthy store must still report success")

        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
        let meals = try container.mainContext.fetch(FetchDescriptor<Meal>())
        let meal = try #require(meals.first)
        #expect(meal.items.count == 2)
        #expect(meal.totalKcal == 240)
    }

    /// A fresh install (no store file yet) has nothing to repair — this
    /// exit must report SUCCESS, or the launch-time gate in OnigiriApp
    /// would wrongly skip repairDanglingFoodReferences on every first run.
    @Test func repairStoreSucceedsWhenNoStoreExistsYet() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Deliberately not creating the directory or the file — this is
        // the exact state a fresh install's App Group container is in.
        let url = dir.appendingPathComponent("NeverCreated.sqlite")

        #expect(LibraryMaintenance.repairStore(at: url))
    }

    /// The regression this whole return-value change exists for
    /// (health-check audit, 2026-08-31): repairStore must report FAILURE
    /// when it cannot actually inspect the store, so a caller can skip the
    /// unconditional SwiftData-level touch that would otherwise crash on
    /// a dangling reference this pass never got to see. A `Void`-returning
    /// repairStore let this exact silent failure run straight into that
    /// touch on every subsequent launch.
    @Test func repairStoreReportsFailureWhenTheStoreCannotBeLoaded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Corrupt.sqlite")

        // A file exists (so the "fresh install" exit doesn't fire) but
        // isn't a valid SQLite store — loadPersistentStores must fail.
        try Data("not a sqlite file".utf8).write(to: url)

        let succeeded = LibraryMaintenance.repairStore(at: url)
        #expect(!succeeded, "a store that fails to load must report failure, not silently succeed")
    }
}
