import XCTest
import OnigiriKit
@testable import Onigiri

/// `refinedFood(...)`'s code-side backstop for the re-derivation
/// weakness CLAUDE.md documents: the on-device model sometimes answers
/// a refine with only what the note named, dropping the rest of the
/// prior estimate's components even though the note never spoke to them
/// (the user, 2026-09-14 — "also has chicken" on a Cheese Quesadilla
/// came back as bare chicken). These tests exercise the merge through
/// the same public entry point the model-backed engines call, standing
/// in for a model answer with a plain array literal — no inference, no
/// opt-in, runs in the default suite.
///
/// Class-level @MainActor for the reason `RefineGroundingTests`
/// documents: these assert on FoodIntelligence types whose members
/// inherit the app target's MainActor default.
@MainActor
final class RefineMergeTests: XCTestCase {
    private let prior = FoodIntelligence.RefinedFood(
        name: "Cheese Quesadilla", serving: "", kcal: 0, sodiumMg: 0,
        components: [
            .init(name: "tortilla", portion: "1 large", kcal: 210, sodiumMg: 460),
            .init(name: "cheese", portion: "1/2 cup", kcal: 230, sodiumMg: 350),
        ])

    /// The bug report, reproduced: an additive note names only the new
    /// part, and a model answer holding just that part must not stand —
    /// the parts it never mentioned come back.
    func testAnUnmentionedComponentMissingFromTheAnswerIsRestored() {
        let food = FoodIntelligence.refinedFood(
            name: "Chicken Quesadilla", serving: "", kcal: 150, sodiumMg: 300,
            fatG: nil, carbsG: nil, proteinG: nil, fiberG: nil, sugarG: nil,
            // The model's answer, standing in for the collapse: only the
            // named addition, tortilla and cheese silently gone.
            components: [.init(name: "chicken", portion: "3 oz", kcal: 150, sodiumMg: 300)],
            prior: prior,
            grounding: .classifierLabels(["quesadilla", "cheese"]),
            note: "also has chicken")
        let names = Set((food?.components ?? []).map { $0.name.lowercased() })
        XCTAssertEqual(names, ["tortilla", "cheese", "chicken"])
        // Restored unchanged, not re-derived — the whole point of a
        // component the note never spoke to.
        XCTAssertEqual(food?.components.first { $0.name == "tortilla" }?.kcal, 210)
    }

    /// The other side of the same rule: a component the note DOES name
    /// is left to the model's own judgment, including a removal — never
    /// forced back just because it vanished.
    func testAMentionedComponentTheModelDroppedIsNotForciblyRestored() {
        let food = FoodIntelligence.refinedFood(
            name: "Cheese Quesadilla", serving: "", kcal: 210, sodiumMg: 460,
            fatG: nil, carbsG: nil, proteinG: nil, fiberG: nil, sugarG: nil,
            // Correctly dropped cheese per the note.
            components: [.init(name: "tortilla", portion: "1 large", kcal: 210, sodiumMg: 460)],
            prior: prior,
            grounding: .classifierLabels(["quesadilla", "cheese"]),
            note: "no cheese")
        let names = Set((food?.components ?? []).map { $0.name.lowercased() })
        XCTAssertEqual(names, ["tortilla"])
    }

    /// The deterministic backstop in the other direction: the note names
    /// a component for removal, and the model's answer keeps it anyway.
    func testANegatedComponentTheModelFailedToDropIsStruckInCode() {
        let food = FoodIntelligence.refinedFood(
            name: "Cheese Quesadilla", serving: "", kcal: 440, sodiumMg: 810,
            fatG: nil, carbsG: nil, proteinG: nil, fiberG: nil, sugarG: nil,
            // Non-compliant answer: cheese is still here despite "no cheese".
            components: [
                .init(name: "tortilla", portion: "1 large", kcal: 210, sodiumMg: 460),
                .init(name: "cheese", portion: "1/2 cup", kcal: 230, sodiumMg: 350),
            ],
            prior: prior,
            grounding: .classifierLabels(["quesadilla", "cheese"]),
            note: "no cheese")
        let names = Set((food?.components ?? []).map { $0.name.lowercased() })
        XCTAssertEqual(names, ["tortilla"])
    }

    /// A component the model kept — even with different figures — is
    /// never reverted to the prior's numbers. Only a component MISSING
    /// from the answer is ever touched.
    func testAComponentTheModelKeptWithChangedFiguresIsLeftAlone() {
        let food = FoodIntelligence.refinedFood(
            name: "Cheese Quesadilla", serving: "", kcal: 140, sodiumMg: 350,
            fatG: nil, carbsG: nil, proteinG: nil, fiberG: nil, sugarG: nil,
            components: [
                .init(name: "tortilla", portion: "1/2 large", kcal: 105, sodiumMg: 230),
                .init(name: "cheese", portion: "1/2 cup", kcal: 230, sodiumMg: 350),
            ],
            prior: prior,
            grounding: .classifierLabels(["quesadilla", "cheese"]),
            note: "I only ate half the tortilla")
        XCTAssertEqual(food?.components.first { $0.name == "tortilla" }?.kcal, 105)
    }
}
