#if canImport(HealthKit)
import Foundation

/// `WatchModel`'s HealthKit surface — every read and write it makes,
/// copied from `HealthKitService`'s own signatures so the service
/// conforms with an EMPTY extension and nothing about it changes
/// (2026-09-24, `plans/PLAN-audit-salvage.md`; the seam
/// `HealthPlanReading` is for `DailyPlanLoader`). It exists so
/// `OnigiriWatchTests` can drive the model against a fake.
///
/// A protocol requirement carries no default arguments, so every caller
/// passes each one explicitly — and each must equal the default it
/// replaced. DEBUG-only probes (`diagnoseIntake`) stay off it.
@MainActor
public protocol WatchHealthWriting: Sendable {
    func shouldRequestAuthorization() async throws -> Bool
    func requestAuthorization() async throws
    func sharingDenied() -> Bool
    func todayFoodEntries(now: Date) async throws -> [FoodLogEntry]
    func dayTotal(of nutrient: TrackedNutrient, for date: Date, now: Date) async throws -> Double
    @discardableResult
    func logFood(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        nutrients: NutrientValues,
        category: FoodCategory?,
        date: Date,
        aiGenerated: Bool,
        quantity: Double,
        mealItems: [LoggedMealItem]
    ) async throws -> UUID
    func deleteFoodEntry(id: UUID) async throws
    @discardableResult
    func logWater(oz: Double, date: Date) async throws -> UUID
}

extension HealthKitService: WatchHealthWriting {}
#endif
