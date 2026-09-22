import Foundation
import Testing
@testable import OnigiriKit

/// The estimated daily burn behind the Fixed budget. It's the number
/// someone's whole calorie allowance is built on, so the refusals matter
/// as much as the arithmetic — a silently wrong budget is worse than a
/// missing suggestion.
struct BasalEstimateTests {
    // 180 lb, 178 cm, 40 — a body the equation is well-characterized for.
    private let weightLb = 180.0, heightCm = 178.0, age = 40

    @Test func restingIsMifflinStJeor() {
        // 180 lb = 81.647 kg
        // 10(81.647) + 6.25(178) − 5(40) + 5 = 816.47 + 1112.5 − 200 + 5
        let male = BasalEstimate.restingKcal(
            weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: .male)
        #expect(male != nil)
        #expect(abs((male ?? 0) - 1_733.97) < 1)

        // The female constant is 166 lower.
        let female = BasalEstimate.restingKcal(
            weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: .female)
        #expect(abs((male ?? 0) - (female ?? 0) - 166) < 0.01)
    }

    /// An unset or non-binary Health value still deserves a usable
    /// number, so it sits at the midpoint rather than being forced into
    /// one of the two.
    @Test func unspecifiedSexLandsBetweenTheOthers() {
        let male = BasalEstimate.restingKcal(weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: .male) ?? 0
        let female = BasalEstimate.restingKcal(weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: .female) ?? 0
        let unspecified = BasalEstimate.restingKcal(weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: .unspecified) ?? 0
        #expect(unspecified < male)
        #expect(unspecified > female)
        #expect(abs(unspecified - (male + female) / 2) < 0.01)
    }

    // MARK: Refusals

    @Test func nonsenseBodiesEstimateNothing() {
        // Each field out of range on its own.
        #expect(BasalEstimate.restingKcal(weightLb: 12, heightCm: heightCm, ageYears: age, sex: .male) == nil)
        #expect(BasalEstimate.restingKcal(weightLb: weightLb, heightCm: 30, ageYears: age, sex: .male) == nil)
        #expect(BasalEstimate.restingKcal(weightLb: weightLb, heightCm: heightCm, ageYears: 3, sex: .male) == nil)
        #expect(BasalEstimate.restingKcal(weightLb: weightLb, heightCm: heightCm, ageYears: 130, sex: .male) == nil)
    }

}
