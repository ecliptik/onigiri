import Foundation
import Testing
@testable import OnigiriKit

struct FoodLogEntryTests {
    private func entry(quantity: Double) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), name: "Hot dog", kcal: 450, sodiumMg: 1500,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            quantity: quantity
        )
    }

    @Test func quantityDefaultsToOnePortion() {
        let plain = FoodLogEntry(
            id: UUID(), name: "Hot dog", kcal: 150, sodiumMg: 500,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(plain.quantity == 1)
    }

    @Test func quantityKeepsValidPortionCounts() {
        #expect(entry(quantity: 3).quantity == 3)
        #expect(entry(quantity: 0.5).quantity == 0.5)
    }

    /// The edit sheet divides totals by quantity — garbage metadata
    /// (another app, a corrupted value) must never make that trap or
    /// produce nonsense, so invalid counts collapse to 1.
    @Test func quantityRejectsUndividableValues() {
        #expect(entry(quantity: 0).quantity == 1)
        #expect(entry(quantity: -2).quantity == 1)
        #expect(entry(quantity: .nan).quantity == 1)
        #expect(entry(quantity: .infinity).quantity == 1)
    }

    /// The metadata slot is plist-typed, so composition rides as a JSON
    /// string — the codec must survive the round trip (names with
    /// quotes/emoji included) and degrade to nothing, never throw.
    @Test func mealItemsCodecRoundTrips() {
        let items = [
            LoggedMealItem(name: "2× Egg", kcal: 140),
            LoggedMealItem(name: "Rice \"bowl\" 🍚", kcal: 210.5),
        ]
        let encoded = LoggedMealItem.encoded(items)
        #expect(encoded != nil)
        #expect(LoggedMealItem.decoded(from: encoded) == items)
    }

    @Test func mealItemsCodecDegradesToEmpty() {
        #expect(LoggedMealItem.encoded([]) == nil)
        #expect(LoggedMealItem.decoded(from: nil) == [])
        #expect(LoggedMealItem.decoded(from: "not json") == [])
        #expect(LoggedMealItem.decoded(from: "{\"name\":\"half\"}") == [])
    }

    @Test func mealItemsDefaultToEmptyForPlainFoods() {
        #expect(entry(quantity: 1).mealItems.isEmpty)
    }
}
