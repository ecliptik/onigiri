import Foundation
import SwiftData

/// The pure export/import merge logic behind Settings' backup feature —
/// moved here from the app target (health-check audit, 2026-08-31) so it
/// can actually be unit tested. This is exactly the class of bug
/// CLAUDE.md's "Library rows" section warns about: an additive,
/// name-based dedup whose own comments describe an "undetectable"
/// UUID-collision failure mode. Sitting untested in the app target for
/// months meant nothing caught a regression here; it now lives beside
/// `LibraryDuplicate`/`LibraryImport`, the rules it depends on.
///
/// The app-target `Onigiri.LibraryTransfer` (same name, different module)
/// stays the public surface every call site uses — it delegates `export`/
/// `importData` straight through to this type, and keeps
/// `handlePickedFile`/`LibraryJSONDocument`, which are UI plumbing
/// (`PhoneSyncService`, SwiftUI's `FileDocument`) that don't belong in a
/// pure-logic package.
public enum LibraryTransfer {
    @MainActor
    public static func export(from context: ModelContext) throws -> Data {
        let foods = try context.fetch(FetchDescriptor<Food>(sortBy: [SortDescriptor(\.name)]))
        let meals = try context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.name)]))
        let goal = try context.fetch(FetchDescriptor<GoalSettings>()).first
        let export = LibraryExport(
            exportedAt: .now,
            foods: foods.map {
                .init(name: $0.name, kcal: $0.kcal, sodiumMg: $0.sodiumMg,
                      servingDescription: $0.servingDescription, barcode: $0.barcode,
                      nutrients: $0.nutrients.isEmpty ? nil : $0.nutrients,
                      isFavorite: $0.isFavorite ? true : nil,
                      category: $0.category,
                      lastUsedAt: $0.lastUsedAt,
                      createdAt: $0.createdAt,
                      aiGenerated: $0.aiGenerated ? true : nil)
            },
            meals: meals.map { meal in
                .init(name: meal.name, items: meal.items.compactMap { item in
                    item.food.map { .init(foodName: $0.name, quantity: item.quantity) }
                }, isFavorite: meal.isFavorite ? true : nil, category: meal.category,
                uuid: meal.uuid, lastUsedAt: meal.lastUsedAt,
                createdAt: meal.createdAt,
                aiGenerated: meal.aiGenerated ? true : nil)
            },
            goal: goal.map {
                .init(targetWeightLb: $0.targetWeightLb, targetDate: $0.targetDate,
                      fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb,
                      mode: $0.mode,
                      startWeightLb: $0.startWeightLb, startedAt: $0.startedAt,
                      startIsManual: $0.startIsManual)
            },
            water: .init(servingOz: SharedStore.waterServingOz, goalOz: SharedStore.waterGoalOz)
        )
        return try export.encoded()
    }

    /// Imports additively: foods and meals whose names already exist are
    /// skipped; the goal and water settings are overwritten when present.
    /// Returns a human-readable summary.
    @MainActor
    public static func importData(_ data: Data, into context: ModelContext) throws -> String {
        let export = try LibraryExport.decode(data)

        let existingFoods = try context.fetch(FetchDescriptor<Food>())
        // `LibraryDuplicate.key`, not a bare `lowercased()`: the app's
        // duplicate rule trims too, and this path used to skip that — so
        // a backup holding " Oats" restored a twin of "Oats" every time.
        var foodsByName: [String: Food] = Dictionary(
            existingFoods.map { (LibraryDuplicate.key($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var addedFoods = 0
        for item in export.foods where foodsByName[LibraryDuplicate.key(item.name)] == nil {
            let food = Food(
                name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
                servingDescription: item.servingDescription, barcode: item.barcode,
                nutrients: item.nutrients ?? NutrientValues(),
                isFavorite: item.isFavorite ?? false,
                category: item.category,
                aiGenerated: item.aiGenerated ?? false
            )
            // Restore recency so Recent/ranked ordering survives the
            // round-trip. Both halves matter: most foods never bump
            // lastUsedAt, so createdAt is their only recency signal —
            // leaving it at the restore timestamp collapsed them into a
            // tie and broke Recent sort. nil on old exports keeps the
            // fresh createdAt (best available for legacy backups).
            food.lastUsedAt = item.lastUsedAt
            if let createdAt = item.createdAt { food.createdAt = createdAt }
            context.insert(food)
            foodsByName[LibraryDuplicate.key(item.name)] = food
            addedFoods += 1
        }

        let existingMeals = try context.fetch(FetchDescriptor<Meal>())
        let existingMealNames = Set(existingMeals.map { LibraryDuplicate.key($0.name) })
        // Every identifier already spoken for — by a live meal, or by an
        // earlier meal in this same import.
        var claimedUUIDs = Set(existingMeals.map(\.uuid))
        var addedMeals = 0
        for mealDef in export.meals where !existingMealNames.contains(LibraryDuplicate.key(mealDef.name)) {
            let items = mealDef.items.compactMap { ref in
                foodsByName[LibraryDuplicate.key(ref.foodName)].map { MealItem(food: $0, quantity: ref.quantity) }
            }
            guard !items.isEmpty else { continue }
            let meal = Meal(
                name: mealDef.name, items: items,
                isFavorite: mealDef.isFavorite ?? false, category: mealDef.category,
                aiGenerated: mealDef.aiGenerated ?? false
            )
            // Keep the exported identity so configured meal widgets
            // survive — unless it is already spoken for. Restamping
            // unconditionally gave two meals one uuid whenever a meal had
            // been RENAMED since the backup: the name guard above stops
            // matching, so a second row is created and used to inherit
            // the first one's identifier.
            if let uuid = LibraryImport.mealUUID(preferring: mealDef.uuid, claimed: claimedUUIDs) {
                meal.uuid = uuid
            }
            claimedUUIDs.insert(meal.uuid)
            meal.lastUsedAt = mealDef.lastUsedAt
            if let createdAt = mealDef.createdAt { meal.createdAt = createdAt }
            context.insert(meal)
            addedMeals += 1
        }

        if let goalDef = export.goal {
            if let existing = try context.fetch(FetchDescriptor<GoalSettings>()).first {
                existing.targetWeightLb = goalDef.targetWeightLb
                existing.targetDate = goalDef.targetDate
                existing.fallbackCurrentWeightLb = goalDef.fallbackCurrentWeightLb
                // nil (old exports) means .lose — GoalSettings' own rule.
                existing.mode = goalDef.mode
                existing.startWeightLb = goalDef.startWeightLb
                existing.startedAt = goalDef.startedAt
                existing.startIsManual = goalDef.startIsManual
            } else {
                context.insert(GoalSettings(
                    targetWeightLb: goalDef.targetWeightLb,
                    targetDate: goalDef.targetDate,
                    fallbackCurrentWeightLb: goalDef.fallbackCurrentWeightLb,
                    mode: goalDef.mode,
                    startWeightLb: goalDef.startWeightLb,
                    startedAt: goalDef.startedAt,
                    startIsManual: goalDef.startIsManual
                ))
            }
        }
        SharedStore.defaults.set(export.water.servingOz, forKey: SharedStore.waterServingKey)
        SharedStore.defaults.set(export.water.goalOz, forKey: SharedStore.waterGoalKey)

        try context.save()
        let foodsPart = "\(addedFoods) food\(addedFoods == 1 ? "" : "s")"
        let mealsPart = "\(addedMeals) meal\(addedMeals == 1 ? "" : "s")"
        var summary = "Imported \(foodsPart) and \(mealsPart)"
        // Skips would otherwise read as failure ("Imported 0 foods ✓"
        // after restoring a full backup), and the goal/water overwrite
        // is destructive enough to deserve naming.
        let skipped = (export.foods.count - addedFoods) + (export.meals.count - addedMeals)
        if skipped > 0 {
            summary += " (\(skipped) already saved)"
        }
        summary += export.goal != nil
            ? "; replaced goal and water settings ✓"
            : "; replaced water settings ✓"
        return summary
    }
}
