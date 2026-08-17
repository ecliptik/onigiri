import XCTest
import OnigiriKit
@testable import Onigiri

/// Does the model actually LIST a photographed menu's dishes?
///
/// The transcript is real Vision output from a real board (a Steak Shack
/// menu, shot sideways in hard sun) captured with
/// `scripts/dump-label-ocr.swift` — 43 runs, 788 characters, dish names
/// and prices all legible. So OCR is not the variable here; this asks the
/// one remaining question, which three rounds of reasoning from symptoms
/// failed to settle (2026-08-16).
///
/// Opt-in like the rest of the eval suite: it needs real inference.
@MainActor
final class MenuDishReadTests: XCTestCase {
    private func transcript() throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "menu-photo-steakshack", withExtension: "json"))
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    /// No model, no opt-in: what does the DETERMINISTIC parser make of
    /// this menu? If it invents calories here, then the 1,150 kcal form
    /// seen on device never involved AI at all — which changes the
    /// diagnosis entirely.
    func testWhatTheDeterministicParserSeesInAMenuPhoto() throws {
        let observations = try transcript()
        let label = LabelParser.parse(observations)
        print("LABELPARSER kcal=\(label.kcal.map { String($0) } ?? "nil") "
            + "name=\(label.name ?? "nil") "
            + "fat=\(label.nutrients.fatG.map { String($0) } ?? "nil") "
            + "carbs=\(label.nutrients.carbsG.map { String($0) } ?? "nil") "
            + "protein=\(label.nutrients.proteinG.map { String($0) } ?? "nil") "
            + "sodium=\(label.sodiumMg.map { String($0) } ?? "nil")")
        print("MENUBOARD rows=\(MenuBoardParser.parse(observations).count)")
        print("SIGNTEXT name=\(SignText.namedFood(in: observations)?.name ?? "nil")")
        print("MENTIONS nutrition=\(FoodImageReader.mentionsNutrition(observations))")
        // The predicate the whole menu path hangs on. False here keeps
        // BOTH model reads (refine, and the screenshot read) away from a
        // picture with no printed figures — either one inventing a
        // calorie value returns a label and the menu is never offered.
        XCTAssertFalse(FoodImageReader.mentionsNutrition(observations),
                       "a menu with no printed nutrition must not read as one")
        XCTAssertNil(label.kcal, "the deterministic parser must find no calories here")
        XCTAssertEqual(SignText.namedFood(in: observations)?.name, "Steak Shack S Menu",
                       "the AI-off floor, and the signature of the bug when AI is unreachable")
    }

    func testTheModelListsTheDishesOnAPhotographedMenu() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ONIGIRI_AI_EVALS"] == "1",
            "AI evals are opt-in: pass TEST_RUNNER_ONIGIRI_AI_EVALS=1")
        // A fresh simulator has AI OFF, so without this the model is
        // never asked and the test proves nothing — which is exactly how
        // it read on the first run (isAvailable=false, onDevice=true).
        SharedStore.defaults.set(true, forKey: AIProviderSettings.enabledKey)
        let observations = try transcript()
        print("TRANSCRIPT runs=\(observations.count) chars=\(observations.map(\.text).joined().count)")
        print("AVAILABLE isAvailable=\(FoodIntelligence.isAvailable) onDevice=\(FoodIntelligence.onDeviceAvailable)")

        let reading = await FoodIntelligence.readMenuDishes(transcript: observations)
        let dishes = reading.dishes
        print("DISHES count=\(dishes.count) restaurant=\(reading.restaurant ?? "nil")")
        for dish in dishes {
            print("  - \(dish.name) | \(dish.section ?? "-") | \(dish.kcal.map { String(Int($0)) } ?? "nil")")
        }
        XCTAssertGreaterThanOrEqual(dishes.count, 4, "the board lists eight plates")
        XCTAssertEqual(reading.restaurant, "Steak Shack")
        // Calories must SCALE with portion. The prompt used to forbid
        // estimating nutrition while the schema demanded a calorie
        // field, so the model filled a mandatory number it had been told
        // not to think about: 2,185 kcal for every plate regardless of
        // size, and a 6x spread across passes on identical input
        // (2026-08-16). Sizes that differ must differ.
        let byName = Dictionary(uniqueKeysWithValues: dishes.map { ($0.name, $0) })
        if let small = byName["Signature 6oz Steak Plate"]?.kcal,
           let large = byName["14oz Steak Plate"]?.kcal {
            XCTAssertLessThan(small, large, "a 14oz plate must beat a 6oz one")
            XCTAssertLessThan(small, 1_500, "a plate lunch is not 2,000 kcal")
        }
    }
}

/// Naming the restaurant a DOCUMENT belongs to, when its metadata does
/// not. Shake Shack's guide carries an InDesign-style filename and says
/// "Shake Shack" in exactly one place: the small-print disclaimer on its
/// last page. That is the page this fixture holds.
@MainActor
final class MenuSourceReadTests: XCTestCase {
    func testTheModelNamesTheRestaurantFromTheSmallPrint() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ONIGIRI_AI_EVALS"] == "1",
                          "set ONIGIRI_AI_EVALS=1 to run the model evals")
        SharedStore.defaults.set(true, forKey: AIProviderSettings.enabledKey)
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "menu-shakeshack-p16", withExtension: "json"))
        let page = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
        let name = await FoodIntelligence.readMenuSource(pages: [page])
        print("SOURCE \(name ?? "nil")")
        XCTAssertEqual(name, "Shake Shack")
    }
}
