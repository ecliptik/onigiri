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
        "sodium_100g":0.25,"sodium_serving":0.1}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.name == "Granola Bar (Acme)")
        #expect(product.kcal == 180)
        #expect(product.sodiumMg == 100)
        #expect(product.servingDescription == "1 bar (40 g)")
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

    @Test func skipsBrandWhenAlreadyInName() throws {
        let json = """
        {"status":1,"product":{"product_name":"Nutella","brands":"Nutella,Ferrero",
        "nutriments":{"energy-kcal_100g":539}}}
        """
        let product = try OpenFoodFactsClient.parse(data: data(json), barcode: "123")
        #expect(product.name == "Nutella")
    }
}
