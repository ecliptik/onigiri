import Foundation
import Testing
@testable import OnigiriKit

/// The no-model floor under the image cascade: what a photo's text says
/// when there's no nutrition panel and no AI to interpret it.
///
/// Both fixtures are the real thing — the photos that reported this
/// (2026-08-02), through the app's own OCR configuration via
/// `scripts/dump-label-ocr.swift`. Every heuristic in SignText was
/// picked against these boxes, so they're the regression they came from.
struct SignTextTests {
    private func fixture(_ name: String) throws -> [LabelObservation] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try JSONDecoder().decode([LabelObservation].self, from: Data(contentsOf: url))
    }

    /// The parser is RIGHT to find nothing here — there is no panel.
    /// Pinned so nobody "fixes" it into inventing one.
    @Test func aSignHasNoPanelToParse() throws {
        #expect(LabelParser.parse(try fixture("sign-bakery-green-onion")).isEmpty)
        #expect(LabelParser.parse(try fixture("sign-bakery-case")).isEmpty)
    }

    @Test func readsTheProductNameOffABakeryCard() throws {
        let label = try #require(SignText.namedFood(in: try fixture("sign-bakery-green-onion")))
        #expect(label.name == "Green Onion")
        // Nothing invented alongside it: this is transcription.
        #expect(label.kcal == nil)
        #expect(label.sodiumMg == nil)
        #expect(!label.aiGenerated)
    }

    /// The price is bigger than nothing on that card and the allergen
    /// line is the widest thing on it; neither is the food.
    @Test func priceAndAllergenLineAreNotNames() throws {
        let transcript = try fixture("sign-bakery-green-onion")
        #expect(!SignText.isPlausibleName("$2.25"))
        #expect(!SignText.isPlausibleName("Allergen Warning! Contains:Wheat. Dairy, Soybean Oil"))
        #expect(!SignText.isPlausibleName("Flour/Sugar/Salt/Egg/Mitk/"))
        #expect(!SignText.isPlausibleName("Net WT 250z"))
        #expect(SignText.name(in: transcript) == "Green Onion")
    }

    /// The case shot is the hard one: a vertical Japanese label is the
    /// TALLEST box in frame, the brand is printed four times, and the
    /// name wraps onto a second line.
    @Test func readsAWrappedNamePastTheBrandAndTheVerticalLabel() throws {
        let label = try #require(SignText.namedFood(in: try fixture("sign-bakery-case")))
        #expect(label.name == "Ham & Cheese Filling Bagel")
    }

    @Test func aRepeatedLineIsPackagingNotTheProduct() throws {
        let transcript = try fixture("sign-bakery-case")
        // SUNMERRY appears four times and is a plausible name on its own
        // — only the repetition rule rules it out.
        #expect(SignText.isPlausibleName("SUNMERRY"))
        #expect(SignText.name(in: transcript)?.contains("Sunmerry") != true)
    }

    /// "Net WT. 2.5oz" OCRs as "Net WT 250z" with language correction
    /// off. Reading that as 25 oz would be ten times wrong.
    @Test func anUnparseableNetWeightIsLeftBlank() throws {
        #expect(SignText.netWeight(in: try fixture("sign-bakery-green-onion")) == nil)
    }

    @Test func aCleanNetWeightIsRead() {
        let transcript = [
            LabelObservation(text: "Net WT 2.5 oz", x: 0.1, y: 0.1, w: 0.2, h: 0.01),
        ]
        #expect(SignText.netWeight(in: transcript) == "2.5 oz")
    }

    @Test func nothingFoodLikeMeansNoName() {
        let transcript = [
            LabelObservation(text: "$4.00", x: 0.1, y: 0.5, w: 0.2, h: 0.04),
            LabelObservation(text: "1234567", x: 0.1, y: 0.4, w: 0.2, h: 0.04),
        ]
        #expect(SignText.namedFood(in: transcript) == nil)
    }

    /// Mixed-case text is left alone — only shouting is normalized.
    @Test func onlyAllCapsIsTitleCased() {
        #expect(SignText.titleCased("GREEN ONION") == "Green Onion")
        #expect(SignText.titleCased("Pain au Chocolat") == "Pain au Chocolat")
    }
}
