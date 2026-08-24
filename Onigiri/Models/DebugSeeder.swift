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

        // A STATE flag replaces whatever goal is already there; a plain
        // seed only fills an empty store.
        //
        // `goalCount == 0` alone made every state flag a silent no-op on
        // the second run: the container keeps its SwiftData store across
        // installs, so `--seed-goal-reached` after any earlier seeded run
        // inserted nothing and left the ordinary 190 lb target in place.
        // `testGoalReachedCelebrationAndContinue` then failed on "Today
        // announces a reached target" — a real assertion about a state
        // the launch argument had quietly declined to set up
        // (2026-08-23). The flags are the only way to reach these states
        // at all, so they must win.
        let args = ProcessInfo.processInfo.arguments
        let reached = args.contains("--seed-goal-reached")
        let milestone = args.contains("--seed-milestone")
        let regained = args.contains("--seed-regained")
        // `--seed-aggressive` counts as a state flag for the same reason
        // the other three do: it exists to put the store somewhere
        // specific, and a flag that silently loses to whatever is
        // already saved is worse than no flag.
        let wantsState = reached || milestone || regained
            || args.contains("--seed-aggressive")
        let existing = (try? context.fetch(FetchDescriptor<GoalSettings>())) ?? []
        if wantsState {
            existing.forEach(context.delete)
            // The goal-reached CARD is acknowledged in defaults, keyed by
            // target — and defaults outlive the store, so re-seeding the
            // state left the announcement permanently dismissed and
            // `testGoalReachedCelebrationAndContinue` failed on its very
            // first assertion the second time it was ever run
            // (2026-08-23). A flag that sets up a state has to clear what
            // would suppress it, or it works exactly once per simulator.
            for key in [
                SharedStore.goalReachedAckTargetKey,
                SharedStore.goalReachedAckCountKey,
                SharedStore.goalReachedAckAtKey,
            ] {
                SharedStore.defaults.removeObject(forKey: key)
            }
        }
        if existing.isEmpty || wantsState {
            // 120 days, not 60. At 60 the seeded goal — 12.2 lb against
            // weigh-ins that drift 202 → 200 — asks for 650 kcal/day,
            // which leaves an average-day budget of ~1,650 against a
            // ~1,743 resting estimate for the seeded body. That is UNDER
            // the body's own baseline, so `isAggressive` fires and every
            // capture of the Goal screen carries an orange pace warning
            // — a correct warning about a bad seed, and a screen nobody
            // can review the ordinary state from (2026-08-23).
            //
            // 120 days asks ~298 kcal/day for a ~2,002 budget, clear of
            // both floors with room to spare, and ~0.7 lb/week is what a
            // representative goal looks like anyway. `--seed-aggressive`
            // keeps the old 60 so the warning and its "Move the date to
            // …" button stay reachable on purpose.
            let days = args.contains("--seed-aggressive") ? 60 : 120
            let target = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
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
            //  --seed-aggressive    the old 60-day target, whose deficit
            //                       drives the budget under the resting
            //                       estimate, so `isAggressive` fires
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
