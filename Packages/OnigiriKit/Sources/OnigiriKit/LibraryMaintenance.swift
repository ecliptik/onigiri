import Foundation
import SwiftData

/// One-time store repairs run at app launch.
public enum LibraryMaintenance {
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
