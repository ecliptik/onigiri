import Testing
import Foundation
@testable import OnigiriWatch
@testable import OnigiriKit

/// `WatchModel`'s logging surface — the watch app's first tests
/// (written in the 2026-09-14 health-check audit, landed 2026-09-24,
/// `plans/PLAN-audit-salvage.md`). Scoped to the write paths (`editEntry`, `deleteEntry`,
/// `logWater`, `log`), which are fully deterministic against
/// `FakeWatchHealth`; `refresh()`/`state` are left untested here because
/// they read `SharedStore`/`sync.goal` — real app-group state this
/// target doesn't control — so a pass on them wouldn't prove anything a
/// unit test can back up. Every write path still calls `refresh()` on
/// success as a real side effect; it runs harmlessly against ambient
/// state and isn't asserted on.
@MainActor
struct WatchModelTests {
    private func entry(
        id: UUID = UUID(), name: String = "Oatmeal", kcal: Double = 300,
        sodiumMg: Double = 140, quantity: Double = 1
    ) -> FoodLogEntry {
        FoodLogEntry(
            id: id, name: name, kcal: kcal, sodiumMg: sodiumMg, date: .now,
            category: .breakfast, quantity: quantity)
    }

    // MARK: logWater

    @Test func logWaterSucceedsAndFlashesTheAmount() async {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        let ok = await model.logWater()
        #expect(ok)
        #expect(health.loggedWaterOz == [SharedStore.waterServingOz])
        #expect(model.flash?.contains("✓") == true)
        #expect(!model.flashIsError)
    }

    @Test func logWaterFailureFlashesAndReturnsFalse() async {
        let health = FakeWatchHealth()
        health.nextError = FakeWatchHealthError()
        let model = WatchModel(health: health)
        let ok = await model.logWater()
        #expect(!ok)
        #expect(health.loggedWaterOz.isEmpty)
        #expect(model.flashIsError)
    }

    // MARK: deleteEntry / undo

    @Test func deleteEntrySucceedsAndOffersUndo() async {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        let target = entry(name: "Yogurt")
        let ok = await model.deleteEntry(target)
        #expect(ok)
        #expect(health.deletedIds == [target.id])
        #expect(model.flash?.contains("Removed Yogurt") == true)
        #expect(model.flashUndo != nil)
    }

    @Test func undoReLogsTheCapturedEntryWhole() async throws {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        // Everything the phone's edit sheet reads back: the per-portion
        // basis (quantity), the meal's composition, the time it was
        // eaten and its ✨ provenance. Undo that drops any of them
        // restores a different entry than the one swiped away.
        let eaten = Date(timeIntervalSinceNow: -3_600)
        let items = [LoggedMealItem(name: "Rice", kcal: 200), LoggedMealItem(name: "Beans", kcal: 110)]
        let target = FoodLogEntry(
            id: UUID(), name: "Burrito bowl", kcal: 620, sodiumMg: 900, date: eaten,
            category: .lunch, nutrients: NutrientValues(fatG: 18),
            aiGenerated: true, quantity: 2, mealItems: items)
        _ = await model.deleteEntry(target)
        let undo = try #require(model.flashUndo)
        undo()
        // undoDelete runs in a Task the flash closure starts — wait for
        // its write rather than guessing how long it takes.
        for _ in 0..<100 where health.loggedFoods.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let logged = try #require(health.loggedFoods.last)
        #expect(logged == FakeWatchHealth.LoggedFood(
            name: "Burrito bowl", kcal: 620, sodiumMg: 900,
            nutrients: NutrientValues(fatG: 18), category: .lunch, date: eaten,
            aiGenerated: true, quantity: 2, mealItems: items))
    }

    @Test func deleteFailureFlashesWithoutOfferingUndo() async {
        let health = FakeWatchHealth()
        health.nextError = FakeWatchHealthError()
        let model = WatchModel(health: health)
        let ok = await model.deleteEntry(entry())
        #expect(!ok)
        #expect(health.deletedIds.isEmpty)
        #expect(model.flashIsError)
        #expect(model.flashUndo == nil)
    }

    // MARK: editEntry — scale + rollback

    @Test func editEntryScalesSodiumAndNutrientsWithKcal() async {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        // 300 kcal / 140 mg sodium logged; edited to 600 kcal should
        // scale sodium to 280 mg (the phone's write-before-delete rule).
        let ok = await model.editEntry(entry(kcal: 300, sodiumMg: 140), kcal: 600)
        #expect(ok)
        #expect(health.loggedFoods.first?.kcal == 600)
        #expect(health.loggedFoods.first?.sodiumMg == 280)
    }

    @Test func editEntryKeepsAMealsComposition() async throws {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        // A logged MEAL resized on the wrist must still be a meal on the
        // phone: its items are the per-portion basis, so they ride
        // through unscaled while the quantity carries the resize — the
        // phone's own edit (LogActions.editFoodEntry) does exactly this.
        let items = [LoggedMealItem(name: "Rice", kcal: 200), LoggedMealItem(name: "Beans", kcal: 110)]
        let meal = FoodLogEntry(
            id: UUID(), name: "Burrito bowl", kcal: 310, sodiumMg: 400, date: .now,
            category: .lunch, quantity: 1, mealItems: items)
        let ok = await model.editEntry(meal, kcal: 620)
        #expect(ok)
        let logged = try #require(health.loggedFoods.first)
        #expect(logged.mealItems == items)
        #expect(logged.quantity == 2)
    }

    @Test func editEntryRollsBackTheNewWriteWhenTheOldDeleteFails() async {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        let original = entry(kcal: 300, sodiumMg: 140)
        // The OLD entry's delete fails; editEntry must delete the entry
        // it JUST wrote rather than leave both live (which would
        // double-count the meal in every total). The rollback delete
        // (of the new id) must still succeed, so only THIS id fails.
        health.failDeleteForId = original.id
        let ok = await model.editEntry(original, kcal: 600)
        #expect(!ok)
        // The new write happened (logFood ran before the failing
        // delete)...
        #expect(health.loggedFoods.count == 1)
        // ...and was rolled back: a delete was attempted, targeting the
        // NEW id the failed logFood call returned, not the original's.
        #expect(health.deletedIds.count == 1)
        #expect(health.deletedIds.first != original.id)
        #expect(model.flashIsError)
    }

    // MARK: log(_:) — SyncedMeal mapping

    @Test func logMapsSyncedMealFieldsIntoTheWrite() async throws {
        let health = FakeWatchHealth()
        let model = WatchModel(health: health)
        let meal = SyncedMeal(
            id: UUID(), name: "Big Salad", kcal: 480, sodiumMg: 610,
            category: FoodCategory.lunch.rawValue,
            nutrients: NutrientValues(fatG: 22),
            items: [])
        let ok = await model.log(meal)
        #expect(ok)
        let logged = try #require(health.loggedFoods.first)
        #expect(logged.name == "Big Salad")
        #expect(logged.kcal == 480)
        #expect(logged.sodiumMg == 610)
        #expect(logged.category == .lunch)
        #expect(logged.nutrients.fatG == 22)
    }

    @Test func logFailureFlashesAndReturnsFalse() async {
        let health = FakeWatchHealth()
        health.nextError = FakeWatchHealthError()
        let model = WatchModel(health: health)
        let ok = await model.log(SyncedMeal(id: UUID(), name: "X", kcal: 1, sodiumMg: 1))
        #expect(!ok)
        #expect(model.flashIsError)
    }

    // MARK: Re-entrancy

    @Test func aSecondLogWhileOneIsInFlightIsRefused() async {
        let health = FakeWatchHealth()
        // Holds the first call's logFood open long enough for the second
        // call to observe isLogging still set.
        health.writeDelay = .milliseconds(200)
        let model = WatchModel(health: health)
        async let first = model.logWater()
        try? await Task.sleep(for: .milliseconds(20))
        let second = await model.logWater()
        #expect(!second)
        _ = await first
        // Only the first call's write actually reached health.
        #expect(health.loggedWaterOz.count == 1)
    }
}
