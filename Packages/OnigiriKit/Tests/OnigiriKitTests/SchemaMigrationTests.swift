import CoreData
import Foundation
import SwiftData
import Testing
@testable import OnigiriKit

/// Pins the store-migration seam ahead of App Store distribution
/// (2026-07-20 audit): the JSON backup path had old-format coverage,
/// but nothing proved an actual pre-v2.7.1 ON-DISK store opens under
/// the current schema. The fixture is built by surgery on the real
/// model — the current shape minus the aiGenerated columns — so it is
/// byte-for-byte what every pre-2.7.1 install wrote, and the reopen
/// takes the exact ModelContainer path a post-update launch takes.
struct SchemaMigrationTests {
    @MainActor
    @Test func preAIGeneratedStoreOpensAndDefaultsUnderCurrentSchema() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("PreAIGenerated.sqlite")

        // Build the old-schema store and seed one Food and one Meal.
        do {
            let bridged = try #require(NSManagedObjectModel.makeManagedObjectModel(
                for: [Food.self, Meal.self, MealItem.self, GoalSettings.self]
            ))
            // The bridged model arrives frozen ("Can't modify an
            // immutable model") — surgery needs a mutable copy.
            let model = try #require(bridged.copy() as? NSManagedObjectModel)
            for entity in model.entities where entity.name == "Food" || entity.name == "Meal" {
                entity.properties.removeAll { $0.name == "aiGenerated" }
            }
            let container = NSPersistentContainer(name: "PreAIGenerated", managedObjectModel: model)
            let description = NSPersistentStoreDescription(url: url)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in #expect(error == nil) }
            let context = container.viewContext
            let food = NSEntityDescription.insertNewObject(forEntityName: "Food", into: context)
            food.setValue("Oats", forKey: "name")
            food.setValue(150.0, forKey: "kcal")
            food.setValue(2.0, forKey: "sodiumMg")
            food.setValue("", forKey: "servingDescription")
            food.setValue(Date.now, forKey: "createdAt")
            food.setValue(false, forKey: "isFavorite")
            let meal = NSEntityDescription.insertNewObject(forEntityName: "Meal", into: context)
            meal.setValue(UUID(), forKey: "uuid")
            meal.setValue("Breakfast", forKey: "name")
            meal.setValue(Date.now, forKey: "createdAt")
            meal.setValue(false, forKey: "isFavorite")
            try context.save()
            let coordinator = container.persistentStoreCoordinator
            try coordinator.persistentStores.forEach { try coordinator.remove($0) }
        }

        // Reopen with the current versioned schema + migration plan.
        // A failure here is the launch-crash class CLAUDE.md documents,
        // from schema mismatch instead of a dangling relationship.
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: OnigiriSchemaV1.self),
            migrationPlan: OnigiriMigrationPlan.self,
            configurations: [config]
        )
        let foods = try container.mainContext.fetch(FetchDescriptor<Food>())
        let food = try #require(foods.first)
        #expect(food.name == "Oats")
        #expect(food.aiGenerated == false)
        let meals = try container.mainContext.fetch(FetchDescriptor<Meal>())
        let meal = try #require(meals.first)
        #expect(meal.aiGenerated == false)
    }
}
