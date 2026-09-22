import Foundation
import Testing
@testable import OnigiriKit

/// The meal builder's member caption. Its whole job is that the Total is
/// readable as a sum of the rows above it, so the contribution — never
/// the per-serving figure — leads every case.
struct MealMemberCaptionTests {
    @Test func oneServingShowsItsOwnCalories() {
        #expect(MealMemberCaption.text(quantity: 1, kcalEach: 220) == "220 kcal")
    }

    @Test func moreThanOneShowsTheContributionThenTheUnitPrice() {
        #expect(MealMemberCaption.text(quantity: 2, kcalEach: 190) == "380 kcal · 190 each")
        #expect(MealMemberCaption.text(quantity: 3, kcalEach: 100) == "300 kcal · 100 each")
    }

    /// Fractions are the case the caption exists for — half a Soylent
    /// belongs in a meal, and 200 kcal is not what it contributes.
    @Test func fractionsContributeLessThanOneServing() {
        #expect(MealMemberCaption.text(quantity: 0.5, kcalEach: 40) == "20 kcal · 40 each")
        #expect(MealMemberCaption.text(quantity: 0.25, kcalEach: 400) == "100 kcal · 400 each")
    }

    /// The stepper steps by 0.25 and the field takes typed decimals, so
    /// "one serving" can arrive as 0.9999999. Exact equality on a Double
    /// would print "220 kcal · 220 each".
    @Test func nearlyOneCountsAsOne() {
        #expect(MealMemberCaption.text(quantity: 0.9999999, kcalEach: 220) == "220 kcal")
        #expect(MealMemberCaption.text(quantity: 1.0000001, kcalEach: 220) == "220 kcal")
    }

    /// An estimate's portion text rides only at one serving — past that
    /// the per-serving figure is worth more than "1 cup", and a third
    /// clause would wrap the row.
    @Test func portionRidesOnlyAtOneServing() {
        #expect(MealMemberCaption.text(quantity: 1, kcalEach: 220, portion: "1 cup")
                == "220 kcal · 1 cup")
        #expect(MealMemberCaption.text(quantity: 2, kcalEach: 220, portion: "1 cup")
                == "440 kcal · 220 each")
        // A library food has no portion text and must not gain a stray
        // separator.
        #expect(MealMemberCaption.text(quantity: 1, kcalEach: 220, portion: "   ") == "220 kcal")
    }

    /// Locale-formatted, like every other number in the app — built with
    /// the same format style rather than a hardcoded "1,900".
    @Test func largeNumbersGroupLikeTheRestOfTheApp() {
        let expected = (1900.0).formatted(.number.precision(.fractionLength(0)))
        #expect(MealMemberCaption.text(quantity: 2, kcalEach: 950).hasPrefix("\(expected) kcal"))
    }

    /// Rounding happens on the PRODUCT, not on the parts — and it is the
    /// format style's own half-to-even, the same rule every other number
    /// in the app rounds by. 20.5 → "20", not "21"; pinned here so a
    /// future rounding change has to be deliberate.
    @Test func theContributionRoundsAfterMultiplying() {
        #expect(MealMemberCaption.text(quantity: 0.5, kcalEach: 41) == "20 kcal · 41 each")
        #expect(MealMemberCaption.text(quantity: 0.5, kcalEach: 43) == "22 kcal · 43 each")
        // Rounding the parts first would give 3 × 33 = 99, not 100.
        #expect(MealMemberCaption.text(quantity: 3, kcalEach: 33.4) == "100 kcal · 33 each")
    }
}
