import Foundation
import Testing
@testable import OnigiriKit

/// When a published row may be offered in place of an estimate
/// (`PublishedNameMatch`). The bar is high on purpose: a database figure
/// beside an estimate reads as the authoritative one, so a wrong offer
/// does more harm than no offer.
struct PublishedNameMatchTests {
    private func matches(_ estimate: String, _ candidate: String) -> Bool {
        PublishedNameMatch.matches(estimate: estimate, candidate: candidate)
    }

    // MARK: The case worth having

    /// The eval's own worst sodium miss: the model puts a Big Mac at
    /// ~2,500 mg where McDonald's publishes ~1,010. A brand prefix on
    /// the candidate is exactly what should match.
    @Test func aBrandedItemMatchesThroughItsBrand() {
        #expect(matches("Big Mac", "Big Mac"))
        #expect(matches("Big Mac", "McDonald's Big Mac"))
        #expect(matches("Big Mac", "Big Mac Burger"))
        #expect(matches("Coca-Cola", "Coca Cola Classic 12 fl oz"))
    }

    // MARK: What must never be offered

    /// A word that changes the food, however small.
    @Test func anAddedWordThatChangesTheFoodIsRefused() {
        #expect(!matches("Big Mac", "Big Mac Sauce"))
        #expect(!matches("Big Mac", "Big Mac Flavored Chips"))
        #expect(!matches("apple", "apple juice"))
        #expect(!matches("vanilla", "vanilla extract"))
    }

    /// A composed dish is not the ingredient it was made from — and
    /// describe-it exists because no database holds the dish.
    @Test func aComposedDishNeverMatchesAnIngredientRow() {
        #expect(!matches("two large scrambled eggs", "Eggs"))
        #expect(!matches("half cup cooked white rice and a fried egg", "White Rice"))
        #expect(!matches("chicken burrito bowl with rice and beans", "Chicken"))
    }

    /// Dropping a word the estimate used means it is a different food,
    /// even when every word present agrees.
    @Test func theCandidateMayNotDropAWord() {
        #expect(!matches("grilled chicken sandwich", "Chicken Sandwich"))
        #expect(!matches("unsalted almonds", "Almonds"))
    }

    /// A candidate may carry a brand and a size, not a paragraph.
    @Test func tooManyAddedWordsIsRefused() {
        #expect(!matches("granola", "Trader Joe's Organic Vanilla Almond Granola Cereal"))
    }

    @Test func nonsenseIsRefused() {
        #expect(!matches("", "Big Mac"))
        #expect(!matches("Big Mac", ""))
        #expect(!matches("a", "a"), "no significant words on either side")
    }

    // MARK: Picking one

    /// Source order decides. A database's own relevance ranking beats
    /// any re-scoring invented here, and the second-best "close enough"
    /// is precisely the offer not worth making.
    @Test func theFirstMatchInSourceOrderWins() {
        func product(_ name: String, kcal: Double) -> ScannedProduct {
            ScannedProduct(
                barcode: "", name: name, kcal: kcal, sodiumMg: 1_010,
                servingDescription: "1 burger", nutrients: NutrientValues())
        }
        let candidates = [
            (name: "Big Mac Sauce", product: product("Big Mac Sauce", kcal: 90)),
            (name: "McDonald's Big Mac", product: product("McDonald's Big Mac", kcal: 550)),
            (name: "Big Mac", product: product("Big Mac", kcal: 563)),
        ]
        let best = PublishedNameMatch.best(for: "Big Mac", among: candidates)
        #expect(best?.kcal == 550, "the sauce is skipped, the first real match taken")
        #expect(PublishedNameMatch.best(for: "chicken parmesan", among: candidates) == nil)
    }
}
