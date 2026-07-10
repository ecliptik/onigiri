import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import OnigiriKit

/// Builds and applies the JSON library export.
enum LibraryTransfer {
    @MainActor
    static func export(from context: ModelContext) throws -> Data {
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
                      category: $0.category)
            },
            meals: meals.map { meal in
                .init(name: meal.name, items: meal.items.compactMap { item in
                    item.food.map { .init(foodName: $0.name, quantity: item.quantity) }
                }, isFavorite: meal.isFavorite ? true : nil, category: meal.category,
                uuid: meal.uuid)
            },
            goal: goal.map {
                .init(targetWeightLb: $0.targetWeightLb, targetDate: $0.targetDate,
                      fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb)
            },
            water: .init(servingOz: SharedStore.waterServingOz, goalOz: SharedStore.waterGoalOz)
        )
        return try export.encoded()
    }

    /// Imports additively: foods and meals whose names already exist are
    /// skipped; the goal and water settings are overwritten when present.
    /// Returns a human-readable summary.
    @MainActor
    static func importData(_ data: Data, into context: ModelContext) throws -> String {
        let export = try LibraryExport.decode(data)

        let existingFoods = try context.fetch(FetchDescriptor<Food>())
        var foodsByName: [String: Food] = Dictionary(
            existingFoods.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var addedFoods = 0
        for item in export.foods where foodsByName[item.name.lowercased()] == nil {
            let food = Food(
                name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
                servingDescription: item.servingDescription, barcode: item.barcode,
                nutrients: item.nutrients ?? NutrientValues(),
                isFavorite: item.isFavorite ?? false,
                category: item.category
            )
            context.insert(food)
            foodsByName[item.name.lowercased()] = food
            addedFoods += 1
        }

        let existingMealNames = Set(try context.fetch(FetchDescriptor<Meal>()).map { $0.name.lowercased() })
        var addedMeals = 0
        for mealDef in export.meals where !existingMealNames.contains(mealDef.name.lowercased()) {
            let items = mealDef.items.compactMap { ref in
                foodsByName[ref.foodName.lowercased()].map { MealItem(food: $0, quantity: ref.quantity) }
            }
            guard !items.isEmpty else { continue }
            let meal = Meal(
                name: mealDef.name, items: items,
                isFavorite: mealDef.isFavorite ?? false, category: mealDef.category
            )
            // Keep the exported identity so configured meal widgets survive.
            if let uuid = mealDef.uuid { meal.uuid = uuid }
            context.insert(meal)
            addedMeals += 1
        }

        if let goalDef = export.goal {
            if let existing = try context.fetch(FetchDescriptor<GoalSettings>()).first {
                existing.targetWeightLb = goalDef.targetWeightLb
                existing.targetDate = goalDef.targetDate
                existing.fallbackCurrentWeightLb = goalDef.fallbackCurrentWeightLb
            } else {
                context.insert(GoalSettings(
                    targetWeightLb: goalDef.targetWeightLb,
                    targetDate: goalDef.targetDate,
                    fallbackCurrentWeightLb: goalDef.fallbackCurrentWeightLb
                ))
            }
        }
        SharedStore.defaults.set(export.water.servingOz, forKey: SharedStore.waterServingKey)
        SharedStore.defaults.set(export.water.goalOz, forKey: SharedStore.waterGoalKey)

        try context.save()
        return "Imported \(addedFoods) foods and \(addedMeals) meals ✓"
    }
}

/// Wraps export data for SwiftUI's fileExporter.
struct LibraryJSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
