import Foundation
import Testing
@testable import OnigiriKit

/// Fixtures are trimmed from live api.nal.usda.gov responses captured
/// 2026-07-13 (query "grapes", dataType Foundation + SR Legacy +
/// Survey (FNDDS)).
struct FoodDataCentralTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    /// MG-unit values round-trip through grams (÷1000 then ×1000), which
    /// binary floating point doesn't keep exact.
    private func expectClose(
        _ value: Double?, _ expected: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let value else {
            Issue.record("value is nil, expected \(expected)", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(value - expected) < 1e-9, sourceLocation: sourceLocation)
    }

    // "Grapes, raw" (Survey/FNDDS 2709237), mapped nutrients verbatim.
    private let grapesRaw = """
    {"fdcId":2709237,"description":"Grapes, raw","dataType":"Survey (FNDDS)",
    "foodNutrients":[
    {"nutrientNumber":"203","nutrientName":"Protein","unitName":"G","value":0.9},
    {"nutrientNumber":"204","nutrientName":"Total lipid (fat)","unitName":"G","value":0.2},
    {"nutrientNumber":"205","nutrientName":"Carbohydrate, by difference","unitName":"G","value":19.4},
    {"nutrientNumber":"208","nutrientName":"Energy","unitName":"KCAL","value":83},
    {"nutrientNumber":"255","nutrientName":"Water","unitName":"G","value":79.04},
    {"nutrientNumber":"262","nutrientName":"Caffeine","unitName":"MG","value":0},
    {"nutrientNumber":"269","nutrientName":"Total Sugars","unitName":"G","value":16.74},
    {"nutrientNumber":"291","nutrientName":"Fiber, total dietary","unitName":"G","value":0.9},
    {"nutrientNumber":"301","nutrientName":"Calcium, Ca","unitName":"MG","value":10},
    {"nutrientNumber":"303","nutrientName":"Iron, Fe","unitName":"MG","value":0.18},
    {"nutrientNumber":"306","nutrientName":"Potassium, K","unitName":"MG","value":224},
    {"nutrientNumber":"307","nutrientName":"Sodium, Na","unitName":"MG","value":5},
    {"nutrientNumber":"317","nutrientName":"Selenium, Se","unitName":"UG","value":0.1},
    {"nutrientNumber":"320","nutrientName":"Vitamin A, RAE","unitName":"UG","value":3},
    {"nutrientNumber":"328","nutrientName":"Vitamin D (D2 + D3)","unitName":"UG","value":0},
    {"nutrientNumber":"401","nutrientName":"Vitamin C, total ascorbic acid","unitName":"MG","value":3.2},
    {"nutrientNumber":"417","nutrientName":"Folate, total","unitName":"UG","value":2},
    {"nutrientNumber":"430","nutrientName":"Vitamin K (phylloquinone)","unitName":"UG","value":14.6},
    {"nutrientNumber":"435","nutrientName":"Folate, DFE","unitName":"UG","value":2},
    {"nutrientNumber":"601","nutrientName":"Cholesterol","unitName":"MG","value":0},
    {"nutrientNumber":"606","nutrientName":"Fatty acids, total saturated","unitName":"G","value":0.054},
    {"nutrientNumber":"645","nutrientName":"Fatty acids, total monounsaturated","unitName":"G","value":0.007},
    {"nutrientNumber":"646","nutrientName":"Fatty acids, total polyunsaturated","unitName":"G","value":0.048}]}
    """

    // "Grape leaves, canned" (SR Legacy 169393): energy in BOTH kJ and
    // KCAL, kJ listed first.
    private let grapeLeaves = """
    {"fdcId":169393,"description":"Grape leaves, canned","dataType":"SR Legacy",
    "foodNutrients":[
    {"nutrientNumber":"268","nutrientName":"Energy","unitName":"kJ","value":287},
    {"nutrientNumber":"208","nutrientName":"Energy","unitName":"KCAL","value":69.0},
    {"nutrientNumber":"307","nutrientName":"Sodium, Na","unitName":"MG","value":2853}]}
    """

    @Test func parsesSearchWithEmbeddedNutrients() throws {
        let json = """
        {"totalHits":46,"currentPage":1,"totalPages":10,
        "foods":[\(grapesRaw),\(grapeLeaves)]}
        """
        let foods = try FoodDataCentralClient.parseSearch(data: data(json))
        #expect(foods.count == 2)

        let grapes = try #require(foods.first)
        #expect(grapes.fdcId == 2709237)
        #expect(grapes.description == "Grapes, raw")
        #expect(grapes.dataType == "Survey (FNDDS)")
        #expect(grapes.kcalPer100g == 83)
        expectClose(grapes.sodiumMgPer100g, 5)
        #expect(grapes.nutrientsPer100g.proteinG == 0.9)
        #expect(grapes.nutrientsPer100g.fatG == 0.2)
        #expect(grapes.nutrientsPer100g.carbsG == 19.4)
        #expect(grapes.nutrientsPer100g.sugarG == 16.74)
        #expect(grapes.nutrientsPer100g.fiberG == 0.9)
        #expect(grapes.nutrientsPer100g.saturatedFatG == 0.054)
        #expect(grapes.nutrientsPer100g.monounsaturatedFatG == 0.007)
        #expect(grapes.nutrientsPer100g.polyunsaturatedFatG == 0.048)
        // Scalar zeros are real label data and stay.
        expectClose(grapes.nutrientsPer100g.cholesterolMg, 0)
        expectClose(grapes.nutrientsPer100g.caffeineMg, 0)
        // Micros land in canonical units: mg for the common ones, µg for
        // the trace set.
        expectClose(grapes.nutrientsPer100g[.calcium], 10)
        expectClose(grapes.nutrientsPer100g[.iron], 0.18)
        expectClose(grapes.nutrientsPer100g[.potassium], 224)
        expectClose(grapes.nutrientsPer100g[.selenium], 0.1)
        expectClose(grapes.nutrientsPer100g[.vitaminA], 3)
        expectClose(grapes.nutrientsPer100g[.vitaminC], 3.2)
        expectClose(grapes.nutrientsPer100g[.vitaminK], 14.6)
        // Zero micros are noise (matching the OFF mapping) — dropped.
        #expect(grapes.nutrientsPer100g[.vitaminD] == nil)
    }

    @Test func energyUsesKcalNotKJ() throws {
        let json = """
        {"foods":[\(grapeLeaves)]}
        """
        let food = try #require(FoodDataCentralClient.parseSearch(data: data(json)).first)
        #expect(food.kcalPer100g == 69.0)
        expectClose(food.sodiumMgPer100g, 2853)
    }

    @Test func prefersFolateDFEOverTotal() throws {
        let json = """
        {"foods":[{"fdcId":1,"description":"Test food","dataType":"Foundation",
        "foodNutrients":[
        {"nutrientNumber":"417","nutrientName":"Folate, total","unitName":"UG","value":10},
        {"nutrientNumber":"435","nutrientName":"Folate, DFE","unitName":"UG","value":17}]}]}
        """
        let food = try #require(FoodDataCentralClient.parseSearch(data: data(json)).first)
        expectClose(food.nutrientsPer100g[.folate], 17)
    }

    @Test func folateTotalIsTheFallback() throws {
        let json = """
        {"foods":[{"fdcId":1,"description":"Test food","dataType":"Foundation",
        "foodNutrients":[
        {"nutrientNumber":"417","nutrientName":"Folate, total","unitName":"UG","value":10}]}]}
        """
        let food = try #require(FoodDataCentralClient.parseSearch(data: data(json)).first)
        expectClose(food.nutrientsPer100g[.folate], 10)
    }

    @Test func dropsRowsWithoutDescription() throws {
        let json = """
        {"foods":[{"fdcId":1,"description":"  ","dataType":"Foundation","foodNutrients":[]},
        \(grapesRaw)]}
        """
        let foods = try FoodDataCentralClient.parseSearch(data: data(json))
        #expect(foods.map(\.fdcId) == [2709237])
    }

    @Test func garbageIsBadResponse() {
        #expect(throws: FoodDataCentralError.badResponse) {
            _ = try FoodDataCentralClient.parseSearch(data: data("<html>502</html>"))
        }
    }

    @Test func intentRankingPutsPlainFoodFirst() throws {
        // Live FDC order for "grapes" put leaves and juice around the raw
        // fruit; the shared intent scoring reorders by name match.
        let json = """
        {"foods":[\(grapeLeaves),\(grapesRaw)]}
        """
        let parsed = try FoodDataCentralClient.parseSearch(data: data(json))
        let ranked = OpenFoodFactsClient.rank(
            parsed, query: "grapes", name: \.description, brand: { _ in nil }
        )
        #expect(ranked.map(\.fdcId) == [2709237, 169393])
    }

    // MARK: - Portions

    @Test func parsesSurveyPortionDescriptions() throws {
        let json = """
        {"fdcId":2709237,"foodPortions":[
        {"sequenceNumber":2,"portionDescription":"1 NLEA serving","gramWeight":126},
        {"sequenceNumber":1,"portionDescription":"1 cup, seedless","gramWeight":151},
        {"sequenceNumber":9,"portionDescription":"Quantity not specified","gramWeight":100}]}
        """
        let portions = try FoodDataCentralClient.parsePortions(data: data(json))
        // Sorted by sequenceNumber; "Quantity not specified" is unusable.
        #expect(portions == [
            FoodPortion(description: "1 cup, seedless", gramWeight: 151),
            FoodPortion(description: "1 NLEA serving", gramWeight: 126),
        ])
    }

    @Test func buildsSRLegacyPortionFromAmountAndModifier() throws {
        let json = """
        {"fdcId":169393,"foodPortions":[
        {"amount":1,"modifier":"leaf","gramWeight":4},
        {"amount":0.25,"modifier":"cup","gramWeight":33.2}]}
        """
        let portions = try FoodDataCentralClient.parsePortions(data: data(json))
        #expect(portions == [
            FoodPortion(description: "1 leaf", gramWeight: 4),
            FoodPortion(description: "0.25 cup", gramWeight: 33.2),
        ])
    }

    @Test func buildsFoundationPortionFromMeasureUnit() throws {
        let json = """
        {"fdcId":747447,"foodPortions":[
        {"amount":1,"measureUnit":{"name":"cup"},"gramWeight":151},
        {"amount":1,"measureUnit":{"name":"undetermined"},"gramWeight":50}]}
        """
        let portions = try FoodDataCentralClient.parsePortions(data: data(json))
        // A placeholder unit name with no other description is unusable.
        #expect(portions == [FoodPortion(description: "1 cup", gramWeight: 151)])
    }

    @Test func skipsPortionsWithoutUsableWeight() throws {
        let json = """
        {"fdcId":1,"foodPortions":[
        {"amount":1,"modifier":"cup","gramWeight":0},
        {"amount":1,"modifier":"slice"}]}
        """
        #expect(try FoodDataCentralClient.parsePortions(data: data(json)).isEmpty)
    }

    @Test func missingPortionsIsEmptyNotAnError() throws {
        #expect(try FoodDataCentralClient.parsePortions(data: data(#"{"fdcId":1}"#)).isEmpty)
    }

    // MARK: - Pick path

    private var grapesPer100g: ScannedProduct {
        ScannedProduct(
            barcode: "fdc:2709237",
            name: "Grapes, raw",
            kcal: 83,
            sodiumMg: 5,
            servingDescription: "per 100 g",
            nutrients: NutrientValues(carbsG: 19.4, micros: ["potassium": 224])
        )
    }

    @Test func pickScalesToTheHouseholdPortion() {
        let scaled = FoodDataCentralClient.scaled(
            grapesPer100g, to: FoodPortion(description: "1 cup, seedless", gramWeight: 151)
        )
        #expect(scaled.servingDescription == "1 cup, seedless (151 g)")
        expectClose(scaled.kcal, 125.33)
        expectClose(scaled.sodiumMg, 7.55)
        expectClose(scaled.nutrients.carbsG, 29.294)
        expectClose(scaled.nutrients[.potassium], 338.24)
    }

    @Test func pickWithoutPortionsStaysPer100g() {
        #expect(FoodDataCentralClient.scaled(grapesPer100g, to: nil) == grapesPer100g)
    }

    @Test func fdcCodeRoundTripsAndRejectsBarcodes() {
        #expect(FoodDataCentralClient.code(for: 2709237) == "fdc:2709237")
        #expect(FoodDataCentralClient.fdcId(fromCode: "fdc:2709237") == 2709237)
        #expect(FoodDataCentralClient.fdcId(fromCode: "0123456789012") == nil)
    }

    @Test func rowProductCarriesInlineNutrients() throws {
        let json = """
        {"foods":[\(grapesRaw)]}
        """
        let food = try #require(FoodDataCentralClient.parseSearch(data: data(json)).first)
        let product = food.per100gProduct
        #expect(product.barcode == "fdc:2709237")
        #expect(product.kcal == 83)
        #expect(product.servingDescription == "per 100 g")
        expectClose(product.nutrients[.potassium], 224)
    }
}
