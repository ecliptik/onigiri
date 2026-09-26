import Testing
@testable import OnigiriKit

/// A serving retyped is a food relabelled, unless its nutrition moves
/// with it. An online row said "1.0g" at 5.6 kcal; it was corrected to
/// "100" and logged at 6 kcal (the user, 2026-09-25).
struct ServingRescaleTests {
    private func close(_ a: Double?, _ b: Double) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 0.001
    }

    /// The case that started it: a bare number takes the old unit.
    @Test func aBareNumberBorrowsTheUnitItReplaces() {
        #expect(close(ServingRescale.factor(from: "1.0g", to: "100"), 100))
        #expect(ServingRescale.completed("100", after: "1.0g") == "100 g")
    }

    @Test func measuresConvert() {
        #expect(close(ServingRescale.factor(from: "100 g", to: "50 g"), 0.5))
        #expect(close(ServingRescale.factor(from: "1 kg", to: "250 g"), 0.25))
        #expect(close(ServingRescale.factor(from: "8 fl oz", to: "12 fl oz"), 1.5))
        #expect(close(ServingRescale.factor(from: "1 oz", to: "56.699 g"), 2))
        #expect(close(ServingRescale.factor(from: "1 l", to: "250 ml"), 0.25))
        #expect(close(ServingRescale.factor(from: "30 grams", to: "60g"), 2))
    }

    /// A label's bracket is its own conversion, so it is the amount.
    @Test func theBracketedMeasureIsTheAmount() {
        #expect(close(ServingRescale.factor(from: "1 cup (240 ml)", to: "120 ml"), 0.5))
        #expect(close(ServingRescale.factor(from: "1 hot dog (57 g)", to: "2 hot dogs (114 g)"), 2))
    }

    /// Two plain counts compare as counts.
    @Test func bareCountsCompare() {
        #expect(close(ServingRescale.factor(from: "1", to: "3"), 3))
    }

    /// Nothing to compare, or nothing honest to say: no preview.
    @Test func incomparableServingsOfferNothing() {
        #expect(ServingRescale.factor(from: "100 g", to: "1 cup") == nil, "no amount to read")
        #expect(ServingRescale.factor(from: "100 g", to: "100 ml") == nil, "no density is guessed")
        #expect(ServingRescale.factor(from: "100 g", to: "100 g") == nil, "no change")
        #expect(ServingRescale.factor(from: "", to: "100 g") == nil)
        #expect(ServingRescale.factor(from: "1 serving", to: "2 servings") == nil,
                "a unit this can't measure isn't guessed at")
    }

    /// A serving that already has a unit keeps it as typed.
    @Test func aMeasuredServingIsLeftAsTyped() {
        #expect(ServingRescale.completed("100 g", after: "1.0g") == "100 g")
        #expect(ServingRescale.completed("2 bars", after: "1 bar") == "2 bars")
    }
}
