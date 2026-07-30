import Foundation
import Testing
@testable import OnigiriKit

/// The name matcher behind AI meal components and logged-meal Contains
/// rows. Its whole contract is "match only what's certain" — the negative
/// cases matter more than the positive ones.
struct ComponentMatchTests {
    // MARK: What must match

    @Test func caseSpacingAndPunctuationAreSpelling() {
        #expect(ComponentMatch.normalized("Cilantro Rice") == ComponentMatch.normalized("cilantro rice"))
        #expect(ComponentMatch.normalized("  Black   Beans ") == ComponentMatch.normalized("black bean"))
        #expect(ComponentMatch.normalized("Chicken, Grilled") == ComponentMatch.normalized("chicken grilled"))
        #expect(ComponentMatch.normalized("Jalapeño") == ComponentMatch.normalized("jalapeno"))
    }

    @Test func simplePluralsFold() {
        #expect(ComponentMatch.normalized("beans") == ComponentMatch.normalized("bean"))
        #expect(ComponentMatch.normalized("Mixed Greens") == ComponentMatch.normalized("mixed green"))
    }

    /// The -ss/-us/-is endings are part of the word, not a plural.
    @Test func wordsEndingInDoubleSOrUsSurvive() {
        #expect(ComponentMatch.normalized("hummus") == "hummus")
        #expect(ComponentMatch.normalized("couscous") == "couscous")
        #expect(ComponentMatch.normalized("Swiss") == "swiss")
        // Too short to risk: "oats" folds, "gas" doesn't.
        #expect(ComponentMatch.normalized("rice") == "rice")
    }

    @Test func indexFindsTheFirstMeaningfulMatch() {
        let library = ["Egg", "Cilantro Rice", "Black Beans"]
        #expect(ComponentMatch.index(of: "cilantro rice", in: library) == 1)
        #expect(ComponentMatch.index(of: "black bean", in: library) == 2)
        #expect(ComponentMatch.index(of: "guacamole", in: library) == nil)
    }

    // MARK: What must NOT match (the load-bearing half)

    /// Word order is identity, not spelling — "rice pudding" is not
    /// "pudding rice". A reordering matcher would silently log dessert.
    @Test func reorderedWordsDoNotMatch() {
        #expect(ComponentMatch.index(of: "pudding rice", in: ["Rice Pudding"]) == nil)
        #expect(ComponentMatch.index(of: "chicken grilled", in: ["Grilled Chicken"]) == nil)
    }

    /// No substring matching: a component is a whole food or nothing.
    @Test func substringsDoNotMatch() {
        #expect(ComponentMatch.index(of: "chicken", in: ["Grilled Chicken Breast"]) == nil)
        #expect(ComponentMatch.index(of: "rice", in: ["Cilantro Rice"]) == nil)
    }

    @Test func emptyOrPunctuationOnlyNeverMatches() {
        #expect(ComponentMatch.index(of: "", in: ["Egg"]) == nil)
        #expect(ComponentMatch.index(of: "   ", in: ["Egg"]) == nil)
        #expect(ComponentMatch.index(of: "—", in: ["Egg"]) == nil)
    }

    // MARK: The logged-meal quantity prefix

    @Test func quantityPrefixIsStripped() {
        #expect(ComponentMatch.strippingQuantityPrefix("2× Egg") == "Egg")
        // Fractions are locale-formatted, so both separators appear.
        #expect(ComponentMatch.strippingQuantityPrefix("1.5× Egg") == "Egg")
        #expect(ComponentMatch.strippingQuantityPrefix("1,5× Egg") == "Egg")
        #expect(ComponentMatch.strippingQuantityPrefix("0.25× Cilantro Rice") == "Cilantro Rice")
    }

    @Test func aNameThatMerelyContainsTheSignSurvives() {
        #expect(ComponentMatch.strippingQuantityPrefix("Salt × Pepper") == "Salt × Pepper")
        #expect(ComponentMatch.strippingQuantityPrefix("× Egg") == "× Egg")
        #expect(ComponentMatch.strippingQuantityPrefix("Egg") == "Egg")
    }

    /// The two halves compose: a logged row's name resolves to a library
    /// food only after its multiplier is gone.
    @Test func strippedPrefixThenMatchesTheLibrary() {
        let stripped = ComponentMatch.strippingQuantityPrefix("3× Black Beans")
        #expect(ComponentMatch.index(of: stripped, in: ["Egg", "Black Beans"]) == 1)
    }
}
