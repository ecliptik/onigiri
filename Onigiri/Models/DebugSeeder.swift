#if DEBUG
import Foundation
import SwiftData
import OnigiriKit

/// Simulator-only: fills the library and goal with sample content so the UI
/// can be exercised without typing. Paired with HealthKitService.seedSampleData.
enum DebugSeeder {
    static func seedLibraryIfEmpty(context: ModelContext) {
        // The UI tests exercise the ONLINE experience (search sections,
        // barcode routes, add-from-empty-search) — the off-by-default
        // privacy stance would skip all of it, so seeded runs opt in.
        // AI stays off here: AI-dependent tests opt in themselves.
        SharedStore.defaults.set(true, forKey: SharedStore.onlineLookupsKey)
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
            // Favorited so the Log sheet's resting Favorites scope —
            // the frame every demo clip opens on — shows a meal row
            // with its mark (the library's meal never made it on
            // camera before v2.12.0's media pass).
            context.insert(Meal(name: "Chicken & rice", items: [
                MealItem(food: chicken),
                MealItem(food: rice),
            ], isFavorite: true, category: "Dinner"))
        }

        // A page-plus of filler so scroll-dependent behavior (search
        // drawer collapse, tab-bar minimize) is reproducible in tests —
        // the four-item library above never scrolls. Opt-in, and only on
        // a fresh install: the library seed is guarded by count (this
        // file has always been idempotent), while the HEALTH seed resets
        // instead — see HealthKitService.clearSeededSamples.
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
            // `--seed-goal-reached` puts the target ABOVE the seeded
            // weigh-ins (which drift 202 → 200 lb), so the goal-reached
            // criterion is met and the celebration can be exercised.
            // Inserted directly, so `GoalUpsert`'s target-below-current
            // rule doesn't apply — which is the only way to reach this
            // state without a month of simulated weight loss.
            // Three states that a fresh simulator cannot otherwise reach
            // without a month of simulated weight change, against the
            // seeded weigh-ins (which drift 202 → 200 lb):
            //  --seed-goal-reached  target ABOVE the weigh-ins, so the
            //                       sustained criterion is met
            //  --seed-milestone     a 210 lb start against a 190 target,
            //                       so the 5 lb mark is passed and the
            //                       target is not
            //  --seed-regained      maintenance held near 193, which the
            //                       weigh-ins now sit well above
            let args = ProcessInfo.processInfo.arguments
            let reached = args.contains("--seed-goal-reached")
            let milestone = args.contains("--seed-milestone")
            let regained = args.contains("--seed-regained")
            // A stamped start too, so the celebration has an ARC to
            // report ("10 lb down") and continuing can be seen to
            // preserve it rather than re-zero at today's weight.
            let started = Calendar.current.date(byAdding: .day, value: -60, to: .now)
            let stamps = reached || milestone
            context.insert(GoalSettings(
                targetWeightLb: reached ? 205 : (regained ? 193 : 190),
                targetDate: target,
                mode: regained ? GoalMode.maintain : nil,
                startWeightLb: stamps ? 210 : nil,
                startedAt: stamps ? started : nil))
        }
        try? context.save()
    }
}
#endif
