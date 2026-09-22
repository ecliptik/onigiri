import Testing
import Foundation
import SwiftData
@testable import OnigiriKit

/// Regression coverage for LibraryTransfer's additive merge (moved from
/// the untested app target, health-check audit, 2026-08-31). This is the
/// exact class of bug CLAUDE.md's "Library rows" section warns about —
/// name-based dedup, UUID reconciliation on re-import — and its own
/// comments describe a failure mode ("two meals share one uuid") as
/// "not detectable" without a test like these.
@MainActor
struct LibraryTransferTests {
    /// Keep the container alive for the test's duration — returning only
    /// a context lets it deallocate and SwiftData traps on use.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Food.self, Meal.self, GoalSettings.self,
            configurations: config
        )
    }

    private func exportPayload(
        foods: [LibraryExport.FoodItem] = [],
        meals: [LibraryExport.MealDef] = [],
        goal: LibraryExport.GoalDef? = nil
    ) throws -> Data {
        try LibraryExport(
            exportedAt: .now, foods: foods, meals: meals, goal: goal,
            water: .init(servingOz: 12, goalOz: 64)
        ).encoded()
    }

    // MARK: - Re-import unchanged

    /// Importing the SAME backup twice must not duplicate anything — the
    /// name-based dedup is the whole point of "additive" import.
    @Test func reimportingTheSameBackupAddsNothingTheSecondTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let data = try exportPayload(foods: [
            .init(name: "Oats", kcal: 150, sodiumMg: 2, servingDescription: "1 cup", barcode: nil),
        ])

        let first = try LibraryTransfer.importData(data, into: context)
        #expect(first.contains("Imported 1 food"))

        let second = try LibraryTransfer.importData(data, into: context)
        #expect(second.contains("Imported 0 foods"))
        #expect(second.contains("1 already saved"))

        let foods = try context.fetch(FetchDescriptor<Food>())
        #expect(foods.count == 1)
    }

    /// The dedup key trims and case-folds (LibraryDuplicate.key) — a
    /// backup holding " Oats" must match an existing "oats", not create
    /// a twin. This regressed once already (a bare `lowercased()` used
    /// to skip the trim).
    @Test func dedupMatchesOnTrimmedCaseInsensitiveName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Food(name: "oats", kcal: 150, sodiumMg: 2))
        try context.save()

        let data = try exportPayload(foods: [
            .init(name: " Oats", kcal: 999, sodiumMg: 999, servingDescription: "", barcode: nil),
        ])
        let summary = try LibraryTransfer.importData(data, into: context)

        #expect(summary.contains("Imported 0 foods"))
        let foods = try context.fetch(FetchDescriptor<Food>())
        #expect(foods.count == 1)
        // The EXISTING row wins — its values, not the backup's.
        #expect(foods.first?.kcal == 150)
    }

    // MARK: - Renamed-meal re-import

    /// A meal renamed since the backup no longer matches by name, so the
    /// import creates a SECOND row — and per LibraryImport.mealUUID, the
    /// original uuid is already claimed by the live (renamed) meal, so
    /// the new row must get a FRESH uuid rather than colliding.
    @Test func renamedMealReimportsAsASecondRowWithAFreshUUID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = Food(name: "Chicken", kcal: 280, sodiumMg: 540)
        context.insert(food)
        let sharedUUID = UUID()
        let liveMeal = Meal(name: "Chicken Bowl (renamed)", items: [MealItem(food: food)])
        liveMeal.uuid = sharedUUID
        context.insert(liveMeal)
        try context.save()

        // The backup remembers the meal under its OLD name, carrying the
        // SAME uuid the live (renamed) meal now holds.
        let data = try exportPayload(
            foods: [.init(name: "Chicken", kcal: 280, sodiumMg: 540, servingDescription: "", barcode: nil)],
            meals: [.init(
                name: "Chicken Bowl", items: [.init(foodName: "Chicken", quantity: 1)],
                uuid: sharedUUID
            )]
        )
        let summary = try LibraryTransfer.importData(data, into: context)
        #expect(summary.contains("Imported 0 foods and 1 meal"))

        let meals = try context.fetch(FetchDescriptor<Meal>())
        #expect(meals.count == 2, "renamed meal must not overwrite or merge with the live one")

        let uuids = Set(meals.map(\.uuid))
        #expect(uuids.count == 2, "two meals must never share one uuid — LogMealIntent resolves by uuid")

        let restored = try #require(meals.first { $0.name == "Chicken Bowl" })
        #expect(restored.uuid != sharedUUID, "the claimed uuid must not be handed to a second meal")
    }

    // MARK: - UUID collision within one import

    /// Two DIFFERENT meals in the SAME backup that happen to carry the
    /// same uuid (a malformed or hand-edited export) must not produce two
    /// live meals sharing one identifier — the second one falls back to a
    /// fresh uuid, same rule as the renamed-meal case, applied within a
    /// single import pass.
    @Test func twoMealsInOneImportNeverEndUpSharingAUUID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let collidingUUID = UUID()
        let data = try exportPayload(
            foods: [
                .init(name: "Rice", kcal: 200, sodiumMg: 5, servingDescription: "", barcode: nil),
                .init(name: "Beans", kcal: 120, sodiumMg: 300, servingDescription: "", barcode: nil),
            ],
            meals: [
                .init(name: "Rice Bowl", items: [.init(foodName: "Rice", quantity: 1)], uuid: collidingUUID),
                .init(name: "Bean Bowl", items: [.init(foodName: "Beans", quantity: 1)], uuid: collidingUUID),
            ]
        )
        let summary = try LibraryTransfer.importData(data, into: context)
        #expect(summary.contains("Imported 2 foods and 2 meals"))

        let meals = try context.fetch(FetchDescriptor<Meal>())
        #expect(meals.count == 2)
        let uuids = Set(meals.map(\.uuid))
        #expect(uuids.count == 2, "a colliding uuid in the SOURCE data must not survive into two live meals")
    }

    /// A meal referencing a food that doesn't exist in the backup (or
    /// failed to import) contributes no items and must be skipped
    /// entirely, not inserted as an empty meal.
    @Test func mealsWithNoResolvableFoodsAreSkipped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let data = try exportPayload(
            meals: [.init(name: "Ghost Meal", items: [.init(foodName: "Nonexistent", quantity: 1)])]
        )
        let summary = try LibraryTransfer.importData(data, into: context)
        #expect(summary.contains("Imported 0 foods and 0 meals"))

        let meals = try context.fetch(FetchDescriptor<Meal>())
        #expect(meals.isEmpty)
    }

    // MARK: - Round trip

    /// export → importData into a fresh store must reproduce the same
    /// foods, meals, and goal — the two halves of the feature are tested
    /// far more often together (Settings' backup flow) than apart.
    @Test func exportThenImportRoundTripsIntoAFreshStore() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let chicken = Food(name: "Chicken", kcal: 280, sodiumMg: 540)
        sourceContext.insert(chicken)
        sourceContext.insert(Meal(name: "Chicken Bowl", items: [MealItem(food: chicken)]))
        sourceContext.insert(GoalSettings(targetWeightLb: 180, targetDate: .now.addingTimeInterval(86400 * 60)))
        try sourceContext.save()

        let data = try LibraryTransfer.export(from: sourceContext)

        let destination = try makeContainer()
        let destinationContext = destination.mainContext
        let summary = try LibraryTransfer.importData(data, into: destinationContext)
        #expect(summary.contains("Imported 1 food and 1 meal"))

        let foods = try destinationContext.fetch(FetchDescriptor<Food>())
        #expect(foods.map(\.name) == ["Chicken"])
        let meals = try destinationContext.fetch(FetchDescriptor<Meal>())
        #expect(meals.first?.totalKcal == 280)
        let goals = try destinationContext.fetch(FetchDescriptor<GoalSettings>())
        #expect(goals.first?.targetWeightLb == 180)
    }
}
