import Testing
@testable import OnigiriKit

/// `ScannedProduct.parsedLabel` — the extension's only currency (it has
/// no food form). Moved out of `OnigiriShare/ShareFlow.swift` and into
/// the kit (health-check audit, 2026-09-14) specifically for the two
/// "empty string → nil" conversions below, which had no test coverage
/// while they lived in the extension.
struct ScannedProductParsedLabelTests {
    private func product(name: String = "Trail Mix", serving: String = "1/4 cup") -> ScannedProduct {
        ScannedProduct(
            barcode: "012345", name: name, kcal: 210, sodiumMg: 65,
            servingDescription: serving, nutrients: NutrientValues(fatG: 12),
            aiGenerated: true, warnings: []
        )
    }

    @Test func carriesTheFieldsThrough() {
        let label = product().parsedLabel
        #expect(label.name == "Trail Mix")
        #expect(label.kcal == 210)
        #expect(label.sodiumMg == 65)
        #expect(label.nutrients.fatG == 12)
        #expect(label.servingDescription == "1/4 cup")
        #expect(label.aiGenerated)
    }

    @Test func anEmptyNameBecomesNilNotAnEmptyString() {
        // A photographed panel never carries a name; a blank ParsedLabel
        // name is what tells the rest of the app "nothing was read here"
        // — an empty STRING would be a different, wrong signal (it reads
        // as "the name is blank" rather than "no name was found").
        #expect(product(name: "").parsedLabel.name == nil)
    }

    @Test func anEmptyServingDescriptionBecomesNil() {
        #expect(product(serving: "").parsedLabel.servingDescription == nil)
    }

    @Test func warningsRideThroughForTheConfirmSheet() {
        let withFinding = ScannedProduct(
            barcode: "0", name: "Soup", kcal: 90, sodiumMg: nil,
            servingDescription: "1 can", nutrients: NutrientValues(),
            warnings: [.init(field: .sodium, severity: .dropped, reason: "810,400 mg sodium isn't possible")]
        )
        #expect(withFinding.parsedLabel.warnings.count == 1)
        #expect(withFinding.parsedLabel.warnings.first?.field == .sodium)
    }
}
