import Foundation
import Testing
@testable import OnigiriKit

struct OpenFoodFactsTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func prefersPerServingValues() throws {
        let json = """
        {"status":1,"product":{"product_name":"Granola Bar","brands":"Acme",
        "serving_size":"1 bar (40 g)",
        "nutriments":{"energy-kcal_100g":450,"energy-kcal_serving":180,
        "sodium_100g":0.25,"sodium_serving":0.1,
        "fat_100g":20,"fat_serving":8,"proteins_serving":4.5,
        "carbohydrates_serving":22,"fiber_serving":3,"sugars_serving":9}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.name == "Granola Bar (Acme)")
        #expect(product.kcal == 180)
        #expect(product.sodiumMg == 100)
        #expect(product.servingDescription == "1 bar (40 g)")
        #expect(product.nutrients.fatG == 8)
        #expect(product.nutrients.proteinG == 4.5)
        #expect(product.nutrients.carbsG == 22)
        #expect(product.nutrients.fiberG == 3)
        #expect(product.nutrients.sugarG == 9)
    }

    @Test func nutrientsFallBackToPer100g() throws {
        let json = """
        {"status":1,"product":{"product_name":"Oats",
        "nutriments":{"energy-kcal_100g":380,"fat_100g":7,"proteins_100g":13,
        "carbohydrates_100g":60,"fiber_100g":10,"sugars_100g":1}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.nutrients.fatG == 7)
        #expect(product.nutrients.fiberG == 10)
        #expect(product.servingDescription == "per 100 g")
    }

    @Test func fallsBackToPer100g() throws {
        let json = """
        {"status":1,"product":{"product_name":"Rice Crackers",
        "nutriments":{"energy-kcal_100g":400,"sodium_100g":0.5}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.kcal == 400)
        #expect(product.sodiumMg == 500)
        #expect(product.servingDescription == "per 100 g")
    }

    @Test func convertsSaltToSodium() throws {
        let json = """
        {"status":1,"product":{"product_name":"Soup",
        "nutriments":{"energy-kcal_100g":50,"salt_100g":2.5}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        // 2.5 g salt ≈ 1 g sodium = 1000 mg
        #expect(product.sodiumMg == 1000)
    }

    @Test func decodesStringNumbers() throws {
        let json = """
        {"status":1,"product":{"product_name":"Juice",
        "nutriments":{"energy-kcal_100g":"46","sodium_100g":"0.01"}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.kcal == 46)
        #expect(product.sodiumMg == 10)
    }

    @Test func unknownBarcodeThrowsNotFound() {
        let json = """
        {"status":0,"product":null}
        """
        #expect(throws: OpenFoodFactsError.self) {
            try OpenFoodFactsClient.parse(data: data(json), barcode: "000")
        }
    }

    @Test func parsesSearchResults() throws {
        let json = """
        {"hits":[
          {"code":"111","product_name":"Blueberries","brands":["BerryCo"]},
          {"code":222,"generic_name":"Blueberry Muffin","brands":"Bakery, Other"},
          {"code":"333","product_name":""},
          {"product_name":"No Code Item"}
        ]}
        """
        let results = try OpenFoodFactsClient.parseSearch(data: data(json))
        #expect(results.count == 2)
        #expect(results[0].name == "Blueberries")
        #expect(results[0].barcode == "111")
        #expect(results[0].brand == "BerryCo")
        #expect(results[1].name == "Blueberry Muffin")
        #expect(results[1].barcode == "222")
        #expect(results[1].brand == "Bakery")
    }

    @Test func parsesLegacySearchResults() throws {
        // The cgi fallback: comma-joined brands, product_name key.
        let json = """
        {"count":"3","products":[
          {"code":"5065015507000","product_name":"Pepperoni","brands":"Properoni, Someone Else"},
          {"code":"123","product_name":"  "},
          {"product_name":"No Code"},
          {"code":"456","product_name":"Plain","brands":null}
        ]}
        """
        let results = try OpenFoodFactsClient.parseLegacySearch(data: data(json))
        #expect(results.count == 2)
        #expect(results[0].barcode == "5065015507000")
        #expect(results[0].name == "Pepperoni")
        #expect(results[0].brand == "Properoni")
        #expect(results[1].name == "Plain")
        #expect(results[1].brand == nil)
    }

    @Test func parsesSaturatedTransFatAndCholesterol() throws {
        let json = """
        {"status":1,"product":{"product_name":"Butter","serving_size":"1 tbsp",
        "nutriments":{"energy-kcal_serving":100,"fat_serving":11,
        "saturated-fat_serving":7,"trans-fat_serving":0.5,
        "cholesterol_serving":0.03}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.nutrients.saturatedFatG == 7)
        #expect(product.nutrients.transFatG == 0.5)
        #expect(abs((product.nutrients.cholesterolMg ?? -1) - 30) < 0.001) // g → mg
    }

    @Test func parsesMicronutrientsPerServing() throws {
        // OFF reports micronutrients in grams; they land in mg/µg.
        let json = """
        {"status":1,"product":{"product_name":"Fortified Cereal",
        "serving_size":"1 cup",
        "nutriments":{"energy-kcal_serving":150,
        "potassium_serving":0.18,"calcium_serving":0.13,"iron_serving":0.0081,
        "vitamin-c_serving":0.006,"vitamin-b12_serving":0.0000024,
        "folates_serving":0.0004}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        func value(_ micro: Micronutrient) -> Double { product.nutrients[micro] ?? -1 }
        #expect(abs(value(.potassium) - 180) < 0.001)   // g → mg
        #expect(abs(value(.calcium) - 130) < 0.001)
        #expect(abs(value(.iron) - 8.1) < 0.001)
        #expect(abs(value(.vitaminC) - 6) < 0.001)
        #expect(abs(value(.vitaminB12) - 2.4) < 0.001)  // g → µg
        #expect(abs(value(.folate) - 400) < 0.001)
        #expect(product.nutrients[.zinc] == nil)
    }

    @Test func micronutrientsFallBackToPer100gAndAltKeys() throws {
        let json = """
        {"status":1,"product":{"product_name":"Spinach",
        "nutriments":{"energy-kcal_100g":23,
        "zinc_100g":"0.011","vitamin-b9_100g":0.0002,
        "vitamin-pp_100g":0.016,"pantothenic-acid_100g":0.005,
        "selenium_100g":0.00005}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(abs((product.nutrients[.zinc] ?? -1) - 11) < 0.001)
        // folate arrives under its vitamin-b9 alias (and as a string number)
        #expect(abs((product.nutrients[.folate] ?? -1) - 200) < 0.001)
        // niacin arrives under OFF's vitamin-pp id
        #expect(abs((product.nutrients[.niacin] ?? -1) - 16) < 0.001)
        #expect(abs((product.nutrients[.pantothenicAcid] ?? -1) - 5) < 0.001)
        #expect(abs((product.nutrients[.selenium] ?? -1) - 50) < 0.001) // g → µg
    }

    @Test func parsesFatSubtypesAndCaffeine() throws {
        let json = """
        {"status":1,"product":{"product_name":"Energy Drink","serving_size":"1 can",
        "nutriments":{"energy-kcal_serving":110,
        "polyunsaturated-fat_serving":1.5,"monounsaturated-fat_serving":2.5,
        "caffeine_serving":0.08}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.nutrients.polyunsaturatedFatG == 1.5)
        #expect(product.nutrients.monounsaturatedFatG == 2.5)
        #expect(abs((product.nutrients.caffeineMg ?? -1) - 80) < 0.001) // g → mg
    }

    @Test func skipsBrandWhenAlreadyInName() throws {
        let json = """
        {"status":1,"product":{"product_name":"Nutella","brands":"Nutella,Ferrero",
        "nutriments":{"energy-kcal_100g":539}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.name == "Nutella")
    }
}
