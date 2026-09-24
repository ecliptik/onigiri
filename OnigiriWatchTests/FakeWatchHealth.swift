import Foundation
@testable import OnigiriKit

/// A `WatchHealthWriting` double — `WatchModel` has no test target of
/// its own before this (health-check audit, 2026-09-14). Records every
/// write so a test can assert what `WatchModel` actually asked for,
/// without touching real HealthKit.
@MainActor
final class FakeWatchHealth: WatchHealthWriting {
    struct LoggedFood: Equatable {
        let name: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        let category: FoodCategory?
        let date: Date
        let aiGenerated: Bool
        let quantity: Double
        let mealItems: [LoggedMealItem]
    }

    private(set) var loggedFoods: [LoggedFood] = []
    private(set) var loggedWaterOz: [Double] = []
    private(set) var deletedIds: [UUID] = []

    var sharingDeniedValue = false
    var todayEntries: [FoodLogEntry] = []
    var dayTotalValue: Double = 0
    /// Set to make the next `logFood`/`deleteFoodEntry`/`logWater` throw.
    var nextError: Error?
    /// Fails ONLY a delete of this specific id — for testing
    /// `editEntry`'s rollback, where the OLD entry's delete must fail
    /// while the rollback delete of the NEW id it just wrote succeeds.
    var failDeleteForId: UUID?
    /// Lets a test hold a write call open to exercise WatchModel's
    /// `isLogging` re-entrancy guard deterministically. Applied to every
    /// write method (logFood, logWater) — whichever the test drives.
    var writeDelay: Duration = .zero

    func shouldRequestAuthorization() async throws -> Bool { false }
    func requestAuthorization() async throws {}
    func sharingDenied() -> Bool { sharingDeniedValue }
    func todayFoodEntries(now: Date) async throws -> [FoodLogEntry] { todayEntries }
    func dayTotal(of nutrient: TrackedNutrient, for date: Date, now: Date) async throws -> Double {
        dayTotalValue
    }

    func logFood(
        name: String, kcal: Double, sodiumMg: Double, nutrients: NutrientValues,
        category: FoodCategory?, date: Date, aiGenerated: Bool, quantity: Double,
        mealItems: [LoggedMealItem]
    ) async throws -> UUID {
        if writeDelay > .zero { try? await Task.sleep(for: writeDelay) }
        if let error = nextError { nextError = nil; throw error }
        loggedFoods.append(LoggedFood(
            name: name, kcal: kcal, sodiumMg: sodiumMg, nutrients: nutrients,
            category: category, date: date, aiGenerated: aiGenerated,
            quantity: quantity, mealItems: mealItems))
        return UUID()
    }

    func deleteFoodEntry(id: UUID) async throws {
        if id == failDeleteForId {
            failDeleteForId = nil
            throw FakeWatchHealthError()
        }
        if let error = nextError { nextError = nil; throw error }
        deletedIds.append(id)
    }

    func logWater(oz: Double, date: Date) async throws -> UUID {
        if writeDelay > .zero { try? await Task.sleep(for: writeDelay) }
        if let error = nextError { nextError = nil; throw error }
        loggedWaterOz.append(oz)
        return UUID()
    }
}

struct FakeWatchHealthError: Error {}
