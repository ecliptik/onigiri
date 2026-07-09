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
        {"products":[
          {"code":"111","product_name":"Blueberries","nutriments":{"energy-kcal_100g":57,"sugars_100g":10,"fiber_100g":2.4}},
          {"code":222,"product_name":"Blueberry Muffin","brands":"Bakery","nutriments":{"energy-kcal_serving":420,"fat_serving":18},"serving_size":"1 muffin"},
          {"code":"333","product_name":""}
        ]}
        """
        let results = try OpenFoodFactsClient.parseSearch(data: data(json))
        #expect(results.count == 2)
        #expect(results[0].name == "Blueberries")
        #expect(results[0].barcode == "111")
        #expect(results[0].kcal == 57)
        #expect(results[0].nutrients.fiberG == 2.4)
        #expect(results[1].name == "Blueberry Muffin (Bakery)")
        #expect(results[1].barcode == "222")
        #expect(results[1].kcal == 420)
        #expect(results[1].servingDescription == "1 muffin")
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
