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
            balanceStyle: "remaining"
        )
        let payload = WatchSync.parse(context)

        #expect(payload.meals == meals)
        #expect(payload.goal == .set(goal))
        #expect(payload.waterServingOz == 12)
        #expect(payload.waterGoalOz == 64)
        #expect(payload.balanceStyle == "remaining")
    }

    @Test func balanceStyleDefaultsToBalance() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        #expect(WatchSync.parse(context).balanceStyle == "balance")
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

    @Test func mealsWithoutCategoryStillDecode() throws {
        // A payload from an older phone that predates category/nutrients.
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Toast","kcal":210,"sodiumMg":190}]"#
        let meals = try JSONDecoder().decode([SyncedMeal].self, from: Data(legacy.utf8))
        #expect(meals[0].name == "Toast")
        #expect(meals[0].category == nil)
        #expect(meals[0].nutrients == nil)
    }
}
