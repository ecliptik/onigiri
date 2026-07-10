import Foundation
import SwiftData
import CoreData

/// One-time store repairs run at app launch.
public enum LibraryMaintenance {
    /// Heal dangling MealItem→Food references BEFORE SwiftData opens the
    /// store. SwiftData traps the process the moment such a relationship
    /// resolves ("backing data could no longer be found"), so the context
    /// based sweep below can't even inspect the damage. Core Data can:
    /// `objectIDs(forRelationshipNamed:)` reads the stored reference
    /// without firing the fault, and `existingObject(with:)` throws
    /// instead of trapping when the target row is gone.
    public static func repairStore(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let model = NSManagedObjectModel.makeManagedObjectModel(
                for: [Food.self, Meal.self, MealItem.self, GoalSettings.self]
              )
        else { return }
        let container = NSPersistentContainer(name: "Onigiri", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        // SwiftData stores track persistent history; without opting in the
        // store mounts read-only and the repair can't save.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var loadFailed = false
        container.loadPersistentStores { _, error in loadFailed = error != nil }
        guard !loadFailed else { return }
        defer {
            let coordinator = container.persistentStoreCoordinator
            coordinator.persistentStores.forEach { try? coordinator.remove($0) }
        }

        let context = container.viewContext
        guard let items = try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MealItem"))
        else { return }
        var repaired = false
        for item in items {
            let foodIDs = item.objectIDs(forRelationshipNamed: "food")
            let dangling = foodIDs.contains { (try? context.existingObject(with: $0)) == nil }
            // No food at all is a phantom 0 kcal line; drop those too.
            guard dangling || foodIDs.isEmpty else { continue }
            if dangling { item.setValue(nil, forKey: "food") }
            context.delete(item)
            repaired = true
        }
        if repaired { try? context.save() }
    }

    /// Delete meal items whose food was removed out from under them.
    ///
    /// Stores written before Food↔MealItem had an inverse relationship can
    /// hold items whose food row no longer exists; resolving such an item's
    /// food and touching any property traps SwiftData with "backing data
    /// could no longer be found". Identifiers are safe to read without
    /// firing the fault, so membership in the live-food set is the test.
    /// Items already nullified (food == nil) are dropped too — a food-less
    /// item only contributes a phantom 0 kcal line to its meal.
    @MainActor
    public static func repairDanglingFoodReferences(context: ModelContext) {
        guard let meals = try? context.fetch(FetchDescriptor<Meal>()),
              let foods = try? context.fetch(FetchDescriptor<Food>()) else { return }
        let liveFoodIDs = Set(foods.map(\.persistentModelID))
        var repaired = false
        for meal in meals {
            let dangling = meal.items.filter { item in
                guard let food = item.food else { return true }
                return !liveFoodIDs.contains(food.persistentModelID)
            }
            guard !dangling.isEmpty else { continue }
            meal.items.removeAll { item in dangling.contains { $0 === item } }
            dangling.forEach(context.delete)
            repaired = true
        }
        if repaired { try? context.save() }
    }
}
