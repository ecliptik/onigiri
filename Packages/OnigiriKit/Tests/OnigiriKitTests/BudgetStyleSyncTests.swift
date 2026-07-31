import Foundation
import Testing
@testable import OnigiriKit

/// Budget style crossing to the watch. The watch DERIVES its own budget
/// from the plan inputs, so a style that doesn't make the trip leaves it
/// computing a different allowance than the phone it mirrors — two
/// answers to one question, which is the bug this model exists to end.
struct BudgetStyleSyncTests {
    @Test func styleAndPinnedBurnAreBothCarried() {
        #expect(WatchSync.budgetStyleKeys.contains(SharedStore.budgetStyleKey))
        #expect(WatchSync.budgetStyleKeys.contains(SharedStore.customExpectedBurnKey))
    }

    /// The dict is all strings, but the pinned burn is READ back with
    /// double(forKey:). Stored as a string it returns 0 — "no pinned
    /// number" — and the watch silently budgets off the average while the
    /// phone uses the pin. Nothing would look broken; the numbers would
    /// just differ.
    @Test func aPinnedBurnSurvivesTheStringTrip() {
        let context = WatchSync.makeContext(
            meals: [], goal: nil, waterServingOz: 8, waterGoalOz: 64,
            trackedMetricSettings: [
                SharedStore.budgetStyleKey: BudgetStyle.fixed.rawValue,
                SharedStore.customExpectedBurnKey: "2450.0",
            ]
        )
        let payload = WatchSync.parse(context)
        let settings = payload.trackedMetricSettings
        #expect(settings?[SharedStore.budgetStyleKey] == BudgetStyle.fixed.rawValue)
        #expect(Double(settings?[SharedStore.customExpectedBurnKey] ?? "") == 2_450)
    }

    /// Always-sent, like the unit preferences: a ride-only-when-set key
    /// would strand an old Fixed on the watch after the phone went back
    /// to Automatic.
    @Test func theStyleIsNotOneOfTheOptionalKeys() {
        #expect(BudgetStyle.resolve(nil) == .automatic)
        #expect(BudgetStyle.resolve(BudgetStyle.fixed.rawValue) == .fixed)
    }
}
