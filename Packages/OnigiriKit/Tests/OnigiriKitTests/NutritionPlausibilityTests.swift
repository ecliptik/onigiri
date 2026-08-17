import Foundation
import Testing
@testable import OnigiriKit

/// The gate every nutrition figure passes (`NutritionPlausibility`).
///
/// The calibration points are named here on purpose: raising a ceiling
/// should mean arguing with a bouillon cube, not with a constant.
struct NutritionPlausibilityTests {
    private func check(
        kcal: Double? = nil, sodium: Double? = nil,
        nutrients: NutrientValues = NutrientValues(), servingGrams: Double? = nil
    ) -> NutritionPlausibility.Reading {
        NutritionPlausibility.check(
            kcal: kcal, sodiumMg: sodium, nutrients: nutrients, servingGrams: servingGrams)
    }

    // MARK: Nothing to say

    /// The overwhelmingly common case: a real label, no findings at all.
    @Test func anOrdinaryLabelPassesSilently() {
        let reading = check(
            kcal: 280, sodium: 850,
            nutrients: NutrientValues(
                fatG: 9, saturatedFatG: 4.5, transFatG: 0, cholesterolMg: 35,
                carbsG: 34, proteinG: 15, fiberG: 4, sugarG: 6),
            servingGrams: 227)
        #expect(reading.findings.isEmpty)
        #expect(reading.kcal == 280)
        #expect(reading.sodiumMg == 850)
    }

    /// Salty food is food. A cup of instant ramen really is ~1,800 mg
    /// beside 380 kcal, and a gate that argues with it is useless.
    @Test func saltyRealFoodSurvives() {
        let reading = check(kcal: 380, sodium: 1_800, servingGrams: 64)
        #expect(reading.findings.isEmpty)
        #expect(reading.sodiumMg == 1_800)
    }

    /// The extreme end of real: a bouillon cube is ~5 kcal and ~1,000 mg
    /// — 200 mg per calorie, just inside the 250 ceiling. This test is
    /// the ceiling's justification.
    @Test func aBouillonCubeIsNotImpossible() {
        let reading = check(kcal: 5, sodium: 1_000)
        #expect(reading.dropped.isEmpty, "200 mg/kcal is a real food")
        #expect(reading.sodiumMg == 1_000)
    }

    /// Sodium with no calories beside it — a broth, a mineral water —
    /// has no ratio to test, and must not be dropped for lacking one.
    @Test func sodiumWithoutCaloriesIsLeftAlone() {
        let reading = check(kcal: 0, sodium: 900)
        #expect(reading.dropped.isEmpty)
        #expect(reading.sodiumMg == 900)
    }

    // MARK: Impossible — dropped, field by field

    /// The incident, in numbers: `Salt & Straw © 2026` × 0.4 × 1000.
    /// The calories were RIGHT and must survive the sodium's removal —
    /// that is the whole shape of this gate.
    @Test func theGaletteKeepsItsCaloriesAndLosesItsSodium() {
        let reading = check(kcal: 300, sodium: 810_400)
        #expect(reading.kcal == 300, "300 kcal was correct and stays")
        #expect(reading.sodiumMg == nil)
        #expect(reading.dropped.map(\.field) == [.sodium])
        #expect(reading.dropped.first?.reason.contains("810,400") == true,
                "the reason names the number the user never saw")
    }

    /// Under the absolute ceiling, caught by the ratio instead: 8,000 mg
    /// beside 20 kcal is 400 mg/kcal.
    @Test func aSaltierThanSaltRatioIsDropped() {
        let reading = check(kcal: 20, sodium: 8_000)
        #expect(reading.sodiumMg == nil)
        #expect(reading.dropped.map(\.field) == [.sodium])
    }

    /// The serving's own weight is the hardest bound there is: pure salt
    /// is 39.3% sodium, so 30 g of anything holds at most ~12 g of it.
    @Test func sodiumHeavierThanTheServingIsDropped() {
        let reading = check(kcal: 100, sodium: 15_000, servingGrams: 30)
        #expect(reading.sodiumMg == nil)
        #expect(reading.dropped.first?.reason.contains("30 g serving") == true)
    }

    @Test func aNutrientHeavierThanItsServingIsDropped() {
        let reading = check(
            kcal: 400, nutrients: NutrientValues(carbsG: 300), servingGrams: 200)
        #expect(reading.nutrients.carbsG == nil)
        #expect(reading.dropped.map(\.field) == [.carbs])
    }

    @Test func absurdEnergyIsDroppedButTheRestSurvives() {
        let reading = check(kcal: 91_000, sodium: 400, nutrients: NutrientValues(proteinG: 12))
        #expect(reading.kcal == nil)
        #expect(reading.sodiumMg == 400, "one bad field doesn't condemn the reading")
        #expect(reading.nutrients.proteinG == 12)
    }

    @Test func negativesAreDropped() {
        let reading = check(kcal: 200, sodium: -5, nutrients: NutrientValues(fatG: -2))
        #expect(reading.sodiumMg == nil)
        #expect(reading.nutrients.fatG == nil)
        #expect(reading.dropped.count == 2)
    }

    // MARK: Suspect — kept, and said out loud

    /// The sibling page's 6,000 mg: wrong, but not impossible, and it
    /// cleared every absolute bound in the app. It is KEPT — the gate
    /// does not get to decide — and marked, which is the only thing that
    /// would have caught it.
    @Test func sixThousandMilligramsIsKeptAndFlagged() {
        let reading = check(kcal: 340, sodium: 6_000)
        #expect(reading.sodiumMg == 6_000, "legal: the user decides")
        #expect(reading.suspect.map(\.field) == [.sodium])
        #expect(reading.dropped.isEmpty)
    }

    @Test func macrosThatContradictTheCaloriesAreFlagged() {
        // 20 g fat + 60 g carbs + 30 g protein ≈ 540 kcal, not 190.
        let reading = check(
            kcal: 190,
            nutrients: NutrientValues(fatG: 20, carbsG: 60, proteinG: 30))
        #expect(reading.kcal == 190)
        #expect(reading.suspect.map(\.field) == [.energy])
    }

    /// Alcohol is 7 kcal/g and isn't a tracked field, so a margarita's
    /// macros legitimately under-explain its calories. The tolerance
    /// exists for exactly this and must not cry wolf.
    @Test func aPartlyExplainedLabelIsNotFlagged() {
        let reading = check(
            kcal: 280, nutrients: NutrientValues(fatG: 10, carbsG: 30, proteinG: 8))
        #expect(reading.suspect.isEmpty, "4·30 + 9·10 + 4·8 = 242, inside 30%")
    }

    /// Fat alone says nothing about the calories — flagging on a
    /// partially filled label would fire on half the app's own reads.
    @Test func oneMacroAloneNeverFlagsTheEnergy() {
        let reading = check(kcal: 500, nutrients: NutrientValues(fatG: 2))
        #expect(reading.findings.isEmpty)
    }

    @Test func aPartLargerThanItsWholeIsFlagged() {
        let reading = check(
            kcal: 200,
            nutrients: NutrientValues(fatG: 4, saturatedFatG: 9, carbsG: 10, sugarG: 20))
        let fields = Set(reading.suspect.map(\.field))
        #expect(fields.contains(.sugar))
        #expect(fields.contains(.saturatedFat))
        #expect(reading.nutrients.sugarG == 20, "flagged, never silently altered")
    }

    /// Labels round to the gram, so sugar 12 inside carbs 11.6 is
    /// rounding rather than a contradiction.
    @Test func roundingIsNotAContradiction() {
        let reading = check(kcal: 100, nutrients: NutrientValues(carbsG: 11.6, sugarG: 12))
        #expect(reading.suspect.isEmpty)
    }

    // MARK: Against real published data

    /// The test that decides whether these thresholds are usable: every
    /// row of seven real chain nutrition guides, through the parser and
    /// the gate. **Nothing may be dropped.** A gate that argues with
    /// published data is worse than no gate — it would teach the user to
    /// ignore it, which is the one failure mode this whole layer exists
    /// to avoid.
    ///
    /// Measured 2026-08-17: 297 rows, 0 dropped, 7 suspect — and every
    /// suspect is real (Shake Shack's Triple SmokeShack really does
    /// carry 3,930 mg; the Chick-fil-A entry that reads 13,030 mg is a
    /// catering TRAY). Flagged, kept, and the user decides.
    @Test func realMenusLoseNothing() throws {
        struct Dump: Decodable { let observations: [LabelObservation] }
        var rowCount = 0
        var suspects: [String] = []
        for name in ["menu-cava-p1", "menu-cava-p2", "menu-chickfila-p1",
                     "menu-chipotle-p1", "menu-mcdonalds-p1", "menu-shakeshack-p1"] {
            let url = try #require(Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            let runs = try JSONDecoder()
                .decode(Dump.self, from: Data(contentsOf: url)).observations
            for row in MenuTableParser.parse(runs) {
                rowCount += 1
                let label = row.parsedLabel
                #expect(label.warnings.allSatisfy { $0.severity != .dropped },
                        "\(name)/\(row.name): published data must survive the gate")
                suspects += label.warnings.filter { $0.severity == .suspect }.map(\.reason)
            }
        }
        #expect(rowCount > 250, "the fixtures still parse (\(rowCount) rows)")
        // Noise check: flagging a tenth of a menu would make the mark
        // meaningless. The 2026-08-17 baseline is 7 of 297.
        #expect(Double(suspects.count) / Double(rowCount) < 0.05,
                "\(suspects.count) of \(rowCount) rows flagged — too noisy to mean anything")
    }

    // MARK: The label door

    @Test func checkedLabelCarriesItsWarnings() {
        var label = ParsedLabel()
        label.kcal = 300
        label.sodiumMg = 810_400
        let checked = NutritionPlausibility.checked(label)
        #expect(checked.kcal == 300)
        #expect(checked.sodiumMg == nil)
        #expect(checked.warnings.map(\.severity) == [.dropped])
        #expect(checked.scannedProduct().warnings.count == 1,
                "and survives the hand-off to the form")
    }
}
