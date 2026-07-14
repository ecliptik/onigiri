import Foundation
import Testing
@testable import OnigiriKit

/// Fixture transcripts are real Vision OCR output captured from label
/// photos with `scripts/dump-label-ocr.swift` (RecognizeTextRequest,
/// .accurate, language correction off) — the exact input the scan
/// pipeline hands the parser, OCR damage included.
struct LabelParserTests {
    private func fixture(_ name: String) throws -> [LabelObservation] {
        struct Dump: Decodable { let observations: [LabelObservation] }
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url)).observations
    }

    private func expectEqual(_ actual: Double?, _ expected: Double, accuracy: Double = 0.01,
                             _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else {
            Issue.record(comment ?? "value is nil, expected \(expected)", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(actual - expected) <= accuracy, comment, sourceLocation: sourceLocation)
    }

    // MARK: Fixtures

    /// Standard FDA vertical panel (rendered image): merged name+value
    /// rows, separate %DV column, OCR-mangled footnote mentioning
    /// "2,000 calories" that must not win over the Calories row.
    @Test func usFDAPanel() throws {
        let label = LabelParser.parse(try fixture("us-fda"))
        #expect(label.servingDescription == "1 cup (227g)")
        expectEqual(label.servingGrams, 227)
        expectEqual(label.kcal, 280)
        expectEqual(label.sodiumMg, 850)
        expectEqual(label.nutrients.fatG, 9)
        expectEqual(label.nutrients.saturatedFatG, 4.5)
        expectEqual(label.nutrients.transFatG, 0)
        expectEqual(label.nutrients.cholesterolMg, 35)
        expectEqual(label.nutrients.carbsG, 34)
        expectEqual(label.nutrients.fiberG, 4)
        expectEqual(label.nutrients.sugarG, 6, "total sugars, not the Added Sugars line")
        expectEqual(label.nutrients.proteinG, 15)
        expectEqual(label.nutrients[.vitaminD], 0)
        expectEqual(label.nutrients[.calcium], 320)
        expectEqual(label.nutrients[.iron], 1.6)
        expectEqual(label.nutrients[.potassium], 510)
        #expect(!label.isPer100g)
    }

    /// Trilingual FR/NL/DE jar photo: per-100g and per-15g-portion
    /// columns, kJ/kcal stacked in-column, comma decimals, salt instead
    /// of sodium, wrapped nutrient names whose value sits on the last
    /// wrap line, and a "b3" misread that must yield nil — not 3.
    @Test func euPer100gPanel() throws {
        let label = LabelParser.parse(try fixture("eu-nutella-fr"))
        expectEqual(label.servingGrams, 15)
        #expect(label.servingDescription == "1 portion (15 g)")
        #expect(!label.isPer100g, "portion weight present, so values convert to per-serving")
        expectEqual(label.kcal, 539 * 0.15, accuracy: 0.1)
        expectEqual(label.nutrients.fatG, 30.9 * 0.15)
        expectEqual(label.nutrients.saturatedFatG, 10.6 * 0.15)
        expectEqual(label.nutrients.carbsG, 57.5 * 0.15)
        expectEqual(label.nutrients.sugarG, 56.3 * 0.15)
        expectEqual(label.sodiumMg, 0.107 * 0.4 * 1000 * 0.15, "salt 0,107 g → sodium, scaled to the portion")
        #expect(label.nutrients.proteinG == nil, "OCR read 6,3 as 'b3' — unparsed stays nil")
        #expect(label.nutrients.fiberG == nil)
    }

    /// Bilingual Canadian panel (iPhone photo): "Per 1/3 cup (30 g)*/
    /// Pour…" serving line, EN/FR name pairs with inline values, and a
    /// vitamin tail that lists only %DV — which must stay nil.
    @Test func canadianBilingualPanel() throws {
        let label = LabelParser.parse(try fixture("ca-bilingual"))
        #expect(label.servingDescription == "1/3 cup (30 g)")
        expectEqual(label.servingGrams, 30)
        expectEqual(label.kcal, 110)
        expectEqual(label.nutrients.fatG, 0)
        expectEqual(label.nutrients.saturatedFatG, 0)
        expectEqual(label.nutrients.transFatG, 0)
        expectEqual(label.nutrients.cholesterolMg, 0)
        expectEqual(label.sodiumMg, 0)
        expectEqual(label.nutrients.carbsG, 25)
        expectEqual(label.nutrients.fiberG, 0)
        expectEqual(label.nutrients.sugarG, 0)
        expectEqual(label.nutrients.proteinG, 2)
        #expect(label.nutrients[.vitaminA] == nil, "%DV only — no amount to read")
        #expect(label.nutrients[.calcium] == nil)
        #expect(label.nutrients[.iron] == nil)
    }

    /// FDA dual-column panel (per serving | per container): the
    /// per-container column and merged "%DV nextvalue" fragments
    /// ("1% 1.5g", "0% Omcg") must all lose to the per-serving column.
    @Test func usDualColumnPanel() throws {
        let label = LabelParser.parse(try fixture("us-dual-column"))
        #expect(label.servingDescription == "3 pretzels (28g)")
        expectEqual(label.servingGrams, 28)
        expectEqual(label.kcal, 110, "per serving, not the 330 per container")
        expectEqual(label.nutrients.fatG, 0.5)
        expectEqual(label.nutrients.saturatedFatG, 0)
        expectEqual(label.nutrients.transFatG, 0)
        expectEqual(label.nutrients.cholesterolMg, 0)
        expectEqual(label.sodiumMg, 400)
        expectEqual(label.nutrients.carbsG, 23, "matched via the 'Total Carb.' abbreviation")
        expectEqual(label.nutrients.fiberG, 2)
        expectEqual(label.nutrients.sugarG, 0.5, "'<1g' applies the half-bound convention")
        expectEqual(label.nutrients.proteinG, 3)
        expectEqual(label.nutrients[.vitaminD], 0)
        expectEqual(label.nutrients[.calcium], 10)
        expectEqual(label.nutrients[.iron], 1.2)
        expectEqual(label.nutrients[.potassium], 90)
    }

    /// Hand-authored OCR damage: O-for-0 in three shapes (Og, Omg,
    /// 16Omg), a comma decimal, a spaced micronutrient unit, a %-only
    /// stray, and a value-less Protein row that must stay nil.
    @Test func noisyCompactPanel() throws {
        let label = LabelParser.parse(try fixture("us-noisy"))
        #expect(label.servingDescription == "2 tbsp (32g)")
        expectEqual(label.servingGrams, 32)
        expectEqual(label.kcal, 190)
        expectEqual(label.nutrients.fatG, 16)
        expectEqual(label.nutrients.saturatedFatG, 3.5, "comma decimal normalized")
        expectEqual(label.nutrients.transFatG, 0, "'Og' fixed up to 0g")
        expectEqual(label.nutrients.cholesterolMg, 0, "'Omg' fixed up to 0mg")
        expectEqual(label.sodiumMg, 160, "'16Omg' fixed up to 160mg")
        expectEqual(label.nutrients.carbsG, 8)
        expectEqual(label.nutrients.fiberG, 3)
        expectEqual(label.nutrients.sugarG, 0.5)
        #expect(label.nutrients.proteinG == nil, "no amount on the row — never guessed")
        expectEqual(label.nutrients[.vitaminD], 2, "'2 mcg' with a space still parses")
        expectEqual(label.nutrients[.calcium], 20)
    }

    // MARK: Targeted behaviors

    @Test func emptyInputParsesToEmptyLabel() {
        let label = LabelParser.parse([])
        #expect(label.isEmpty)
        #expect(label.servingDescription == nil)
        #expect(label.servingGrams == nil)
    }

    @Test func per100gWithoutServingWeightStaysPer100g() {
        let label = LabelParser.parse([
            LabelObservation(text: "Nutrition Information", x: 0.05, y: 0.90, w: 0.6, h: 0.04),
            LabelObservation(text: "Per 100g", x: 0.05, y: 0.80, w: 0.3, h: 0.03),
            LabelObservation(text: "Salt", x: 0.05, y: 0.50, w: 0.15, h: 0.03),
            LabelObservation(text: "1.2g", x: 0.55, y: 0.50, w: 0.12, h: 0.03),
        ])
        #expect(label.isPer100g)
        #expect(label.servingDescription == "per 100 g")
        expectEqual(label.sodiumMg, 480, "salt 1.2 g × 0.4 → sodium, left at the per-100g basis")
    }

    @Test func kilojouleOnlyEnergyConverts() {
        let label = LabelParser.parse([
            LabelObservation(text: "Energy", x: 0.05, y: 0.60, w: 0.2, h: 0.03),
            LabelObservation(text: "850 kJ", x: 0.55, y: 0.60, w: 0.15, h: 0.03),
        ])
        expectEqual(label.kcal, 850 / 4.184, accuracy: 0.1)
    }

    @Test func numericNormalization() {
        #expect(LabelParser.normalizedNumericText("Og") == "0g")
        #expect(LabelParser.normalizedNumericText("O mg") == "0 mg")
        #expect(LabelParser.normalizedNumericText("16Omg") == "160mg")
        #expect(LabelParser.normalizedNumericText("1O2g") == "102g")
        #expect(LabelParser.normalizedNumericText("30,9") == "30.9")
        #expect(LabelParser.normalizedNumericText("Only") == "Only", "words keep their Os")
        #expect(LabelParser.normalizedNumericText("Omega") == "Omega")
    }
}
