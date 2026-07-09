#if DEBUG
import Foundation
import SwiftData

/// Simulator-only: fills the library and goal with sample content so the UI
/// can be exercised without typing. Paired with HealthKitService.seedSampleData.
enum DebugSeeder {
    static func seedLibraryIfEmpty(context: ModelContext) {
        let foodCount = (try? context.fetchCount(FetchDescriptor<Food>())) ?? 0
        if foodCount == 0 {
            let chicken = Food(name: "Chicken breast", kcal: 280, sodiumMg: 540, servingDescription: "8 oz")
            let rice = Food(name: "Rice bowl", kcal: 320, sodiumMg: 10, servingDescription: "1 bowl")
            let eggs = Food(name: "Two eggs", kcal: 156, sodiumMg: 124, servingDescription: "2 large")
            let shake = Food(name: "Protein shake", kcal: 180, sodiumMg: 230, servingDescription: "12 oz")
            for food in [chicken, rice, eggs, shake] {
                context.insert(food)
            }
            context.insert(Meal(name: "Chicken & rice", items: [
                MealItem(food: chicken),
                MealItem(food: rice),
            ]))
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
