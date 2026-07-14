#if DEBUG
import Foundation
import SwiftData
import OnigiriKit

/// Simulator-only: fills the library and goal with sample content so the UI
/// can be exercised without typing. Paired with HealthKitService.seedSampleData.
enum DebugSeeder {
    static func seedLibraryIfEmpty(context: ModelContext) {
        let foodCount = (try? context.fetchCount(FetchDescriptor<Food>())) ?? 0
        if foodCount == 0 {
            let chicken = Food(name: "Chicken breast", kcal: 280, sodiumMg: 540, servingDescription: "8 oz",
                               nutrients: NutrientValues(fatG: 6, carbsG: 0, proteinG: 52), category: "Dinner")
            let rice = Food(name: "Rice bowl", kcal: 320, sodiumMg: 10, servingDescription: "1 bowl",
                            nutrients: NutrientValues(fatG: 0.6, carbsG: 70, proteinG: 6, fiberG: 1), category: "Dinner")
            let eggs = Food(name: "Two eggs", kcal: 156, sodiumMg: 124, servingDescription: "2 large",
                            nutrients: NutrientValues(fatG: 10.6, carbsG: 1.1, proteinG: 12.6), category: "Breakfast")
            let shake = Food(name: "Protein shake", kcal: 180, sodiumMg: 230, servingDescription: "12 oz",
                             nutrients: NutrientValues(fatG: 3, carbsG: 9, proteinG: 30, sugarG: 2),
                             isFavorite: true, category: "Snack")
            for food in [chicken, rice, eggs, shake] {
                context.insert(food)
            }
            context.insert(Meal(name: "Chicken & rice", items: [
                MealItem(food: chicken),
                MealItem(food: rice),
            ], category: "Dinner"))
        }

        // A page-plus of filler so scroll-dependent behavior (search
        // drawer collapse, tab-bar minimize) is reproducible in tests —
        // the four-item library above never scrolls. Opt-in, and only
        // on a fresh install (every seeding launch ADDS, per CLAUDE.md).
        if foodCount == 0,
           ProcessInfo.processInfo.arguments.contains("--seed-big-library") {
            for index in 1...30 {
                context.insert(Food(
                    name: "Filler food \(index)", kcal: Double(100 + index),
                    sodiumMg: Double(10 * index), servingDescription: "1 serving",
                    category: "Snack"
                ))
            }
        }

        let goalCount = (try? context.fetchCount(FetchDescriptor<GoalSettings>())) ?? 0
        if goalCount == 0 {
            let target = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
            context.insert(GoalSettings(targetWeightLb: 190, targetDate: target))
        }
        try? context.save()
    }
}
#endif
