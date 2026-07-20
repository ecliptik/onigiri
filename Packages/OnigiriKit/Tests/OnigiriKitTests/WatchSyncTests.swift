import Testing
import Foundation
@testable import OnigiriKit

struct WatchSyncTests {
    @Test func contextRoundTripsAllFields() {
        let meals = [SyncedMeal(
            id: UUID(), name: "Oatmeal", kcal: 320, sodiumMg: 140,
            category: "Breakfast", nutrients: NutrientValues(fiberG: 4)
        )]
        let goal = SyncedGoal(
            targetWeightLb: 170,
            targetDate: Date(timeIntervalSince1970: 1_800_000_000),
            fallbackCurrentWeightLb: 190
        )
        let context = WatchSync.makeContext(
            meals: meals,
            goal: goal,
            waterServingOz: 12,
            waterGoalOz: 64,
            balanceStyle: "remaining",
            foodIcon: "bento",
            waterIcon: "wave"
        )
        let payload = WatchSync.parse(context)

        #expect(payload.meals == meals)
        #expect(payload.goal == .set(goal))
        #expect(payload.waterServingOz == 12)
        #expect(payload.waterGoalOz == 64)
        #expect(payload.balanceStyle == "remaining")
        #expect(payload.foodIcon == "bento")
        #expect(payload.waterIcon == "wave")
    }

    @Test func recentFoodsAndGoalModeRoundTrip() {
        let recents = [SyncedMeal(id: UUID(), name: "Banana", kcal: 105, sodiumMg: 1)]
        let favorites = [SyncedMeal(id: UUID(), name: "Protein shake", kcal: 180, sodiumMg: 230)]
        let goal = SyncedGoal(
            targetWeightLb: 170, targetDate: .distantFuture,
            fallbackCurrentWeightLb: nil, mode: GoalMode.maintain
        )
        let context = WatchSync.makeContext(
            meals: [], recentFoods: recents, favorites: favorites, goal: goal,
            waterServingOz: 12, waterGoalOz: 64
        )
        let payload = WatchSync.parse(context)
        #expect(payload.recentFoods == recents)
        #expect(payload.favorites == favorites)
        guard case .set(let synced) = payload.goal else {
            Issue.record("goal did not round-trip")
            return
        }
        #expect(synced.isMaintenance)
    }

    // A pre-1.6 phone's context has no recentFoods key — keep, not clear.
    @Test func missingRecentFoodsMeansKeep() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        var stripped = context
        stripped.removeValue(forKey: "sync.recentFoods")
        #expect(WatchSync.parse(stripped).recentFoods == nil)
    }

    @Test func iconsDefaultToSFSymbols() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        let payload = WatchSync.parse(context)
        #expect(payload.foodIcon == "sfFork")
        #expect(payload.waterIcon == "sfDrop")
    }

    @Test func balanceStyleDefaultsToRemaining() {
        // "kcal left" is the default headline (2026-07-16); "balance" is
        // the opt-in signed view.
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        #expect(WatchSync.parse(context).balanceStyle == "remaining")
    }

    @Test func absentGoalMeansClear() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        #expect(WatchSync.parse(context).goal == .clear)
    }

    // Version-skewed payloads must not wipe the watch's last good data:
    // present-but-undecodable is "keep", not "clear".
    @Test func corruptDataKeepsLastGoodCopy() {
        var context = WatchSync.makeContext(
            meals: [SyncedMeal(id: UUID(), name: "Oatmeal", kcal: 320, sodiumMg: 140)],
            goal: SyncedGoal(targetWeightLb: 170, targetDate: .distantFuture, fallbackCurrentWeightLb: nil),
            waterServingOz: 12, waterGoalOz: 64
        )
        context[WatchSync.mealsKey] = Data("not json".utf8)
        context[WatchSync.goalKey] = Data("not json".utf8)
        let payload = WatchSync.parse(context)
        #expect(payload.meals == nil)
        #expect(payload.goal == .keep)
    }

    // The phone's plan inputs (day-stamped burn/weight) and log stamp
    // ride the context so the watch's budget matches the phone's and a
    // phone log wakes the complications.
    @Test func planInputsAndLogStampRoundTrip() {
        let context = WatchSync.makeContext(
            meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64,
            planBurnKcal: 2750, planBurnDay: "2026-07-20",
            planWeightLb: 185.4, planWeightDay: "2026-07-20",
            lastLogAt: 1_784_500_000
        )
        let payload = WatchSync.parse(context)
        #expect(payload.planBurnKcal == 2750)
        #expect(payload.planBurnDay == "2026-07-20")
        #expect(payload.planWeightLb == 185.4)
        #expect(payload.planWeightDay == "2026-07-20")
        #expect(payload.lastLogAt == 1_784_500_000)
    }

    // An older phone's context has none of the plan-input keys — nil all
    // the way through (store() then keeps whatever the watch last had).
    @Test func missingPlanInputsStayNil() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        let payload = WatchSync.parse(context)
        #expect(payload.planBurnKcal == nil)
        #expect(payload.planBurnDay == nil)
        #expect(payload.planWeightLb == nil)
        #expect(payload.planWeightDay == nil)
        #expect(payload.lastLogAt == nil)
    }

    // A value without its day stamp must not enter the context — the
    // watch could never judge its freshness.
    @Test func planValueWithoutItsDayIsDropped() {
        let context = WatchSync.makeContext(
            meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64,
            planBurnKcal: 2750, planBurnDay: nil,
            planWeightLb: nil, planWeightDay: "2026-07-20"
        )
        let payload = WatchSync.parse(context)
        #expect(payload.planBurnKcal == nil)
        #expect(payload.planWeightDay == nil)
    }

    @Test func mealsWithoutCategoryStillDecode() throws {
        // A payload from an older phone that predates category/nutrients.
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Toast","kcal":210,"sodiumMg":190}]"#
        let meals = try JSONDecoder().decode([SyncedMeal].self, from: Data(legacy.utf8))
        #expect(meals[0].name == "Toast")
        #expect(meals[0].category == nil)
        #expect(meals[0].nutrients == nil)
    }
}
