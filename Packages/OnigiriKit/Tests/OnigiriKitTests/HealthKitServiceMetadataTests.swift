import Testing
import Foundation
import HealthKit
@testable import OnigiriKit

/// Regression coverage for `HealthKitService.foodMetadata` — the pure
/// half of `logFood`'s write (health-check audit, 2026-08-31).
/// `HealthKitService` itself needs a live HealthKit store and has no
/// test coverage anywhere in the repo; this is the load-bearing part of
/// it that CAN be tested without one. CLAUDE.md's "Logging: HealthKit is
/// the store" section names the exact risk: "any new log/re-log path
/// must carry them ALL through or edits regress and history silently
/// loses detail." These tests exist so a regression in that carrying-
/// through fails a test instead of silently shipping.
@MainActor
struct HealthKitServiceMetadataTests {
    private func metadata(
        name: String = "Oats",
        category: FoodCategory? = nil,
        aiGenerated: Bool = false,
        quantity: Double = 1,
        mealItems: [LoggedMealItem] = []
    ) -> [String: Any] {
        HealthKitService.foodMetadata(
            name: name, category: category, aiGenerated: aiGenerated,
            quantity: quantity, mealItems: mealItems
        )
    }

    // MARK: - Always present

    @Test func nameAndUserEnteredFlagAreAlwaysPresent() {
        let meta = metadata(name: "Chicken Bowl")
        #expect(meta[HKMetadataKeyFoodType] as? String == "Chicken Bowl")
        #expect(meta[HKMetadataKeyWasUserEntered] as? Bool == true)
    }

    // MARK: - Meal category

    @Test func categoryKeyCarriesTheSlotWhenGiven() {
        let meta = metadata(category: .lunch)
        #expect(meta[HealthKitService.mealCategoryMetadataKey] as? String == FoodCategory.lunch.rawValue)
    }

    @Test func categoryKeyIsAbsentWhenNil() {
        let meta = metadata(category: nil)
        #expect(meta[HealthKitService.mealCategoryMetadataKey] == nil,
                "an absent category means 'infer from time of day' — the key must not exist at all, not exist as nil")
    }

    // MARK: - AI-generated mark

    @Test func aiGeneratedKeyIsPresentOnlyWhenTrue() {
        let meta = metadata(aiGenerated: true)
        #expect(meta[HealthKitService.aiGeneratedMetadataKey] as? Bool == true)
    }

    @Test func aiGeneratedKeyIsAbsentWhenFalse() {
        let meta = metadata(aiGenerated: false)
        #expect(meta[HealthKitService.aiGeneratedMetadataKey] == nil,
                "the key must be ABSENT, not `false` — read-back treats absence and false identically, but the write side must match the field's own doc contract")
    }

    // MARK: - Quantity

    @Test func quantityKeyIsAbsentAtTheDefaultOfOne() {
        let meta = metadata(quantity: 1)
        #expect(meta[HealthKitService.quantityMetadataKey] == nil,
                "absent means 1 by the field's own contract — writing 1 explicitly would still read back correctly, but every other single-portion log in the store omits it, and a mismatch would look like a format drift")
    }

    @Test func quantityKeyCarriesAnyOtherPositiveFiniteValue() {
        let meta = metadata(quantity: 3)
        #expect(meta[HealthKitService.quantityMetadataKey] as? Double == 3,
                "'3 hot dogs' must edit as 3, not as one triple-sized serving — this is what the edit sheet divides by")
    }

    @Test func quantityKeyCarriesFractionalValues() {
        let meta = metadata(quantity: 0.5)
        #expect(meta[HealthKitService.quantityMetadataKey] as? Double == 0.5)
    }

    /// Defensive guard in the source: a zero, negative, or non-finite
    /// quantity must never reach the store — Today's row labels cast
    /// this value, and an absurd figure crash-loops that screen.
    @Test func quantityKeyIsAbsentForNonPositiveOrNonFiniteValues() {
        for bad in [0.0, -1.0, Double.infinity, Double.nan] {
            let meta = metadata(quantity: bad)
            #expect(meta[HealthKitService.quantityMetadataKey] == nil,
                    "quantity \(bad) must not reach the store")
        }
    }

    // MARK: - Meal composition

    @Test func mealItemsKeyIsAbsentWhenEmpty() {
        let meta = metadata(mealItems: [])
        #expect(meta[HealthKitService.mealItemsMetadataKey] == nil,
                "empty means 'plain food, or a meal logged before the key existed' — must not encode as an empty-array string")
    }

    @Test func mealItemsKeyCarriesTheEncodedBreakdown() throws {
        let items = [LoggedMealItem(name: "Rice", kcal: 200), LoggedMealItem(name: "Beans", kcal: 120)]
        let meta = metadata(mealItems: items)
        let encoded = try #require(meta[HealthKitService.mealItemsMetadataKey] as? String)
        #expect(LoggedMealItem.decoded(from: encoded) == items,
                "must round-trip through the exact decoder the edit/Contains-row path uses")
    }

    // MARK: - All four keys together (the actual regression shape)

    /// The shape every "add a field to the log write path" PR risks
    /// getting wrong: ALL FOUR optional keys present at once, none
    /// dropped, none corrupting another. A regression that forgets to
    /// thread one new field through often does so by restructuring this
    /// exact dictionary literal.
    @Test func allFourOptionalKeysCoexistWithoutDroppingOrCorruptingEachOther() throws {
        let items = [LoggedMealItem(name: "Chicken", kcal: 280)]
        let meta = metadata(category: .dinner, aiGenerated: true, quantity: 2, mealItems: items)

        #expect(meta[HealthKitService.mealCategoryMetadataKey] as? String == FoodCategory.dinner.rawValue)
        #expect(meta[HealthKitService.aiGeneratedMetadataKey] as? Bool == true)
        #expect(meta[HealthKitService.quantityMetadataKey] as? Double == 2)
        let encoded = try #require(meta[HealthKitService.mealItemsMetadataKey] as? String)
        #expect(LoggedMealItem.decoded(from: encoded) == items)
    }
}
