import Testing
import Foundation
@testable import OnigiriKit

struct WatchSyncTests {
    @Test func contextRoundTripsAllFields() {
        let meals = [SyncedMeal(id: UUID(), name: "Oatmeal", kcal: 320, sodiumMg: 140)]
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
        #expect(payload.goal == goal)
        #expect(payload.waterServingOz == 12)
        #expect(payload.waterGoalOz == 64)
        #expect(payload.balanceStyle == "remaining")
    }

    @Test func balanceStyleDefaultsToBalance() {
        let context = WatchSync.makeContext(meals: [], goal: nil, waterServingOz: 12, waterGoalOz: 64)
        #expect(WatchSync.parse(context).balanceStyle == "balance")
    }
}
