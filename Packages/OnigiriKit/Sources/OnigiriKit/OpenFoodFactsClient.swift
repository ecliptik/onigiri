import Foundation

/// A product looked up by barcode, reduced to what Onigiri tracks.
public struct ScannedProduct: Sendable, Equatable {
    public let barcode: String
    public let name: String
    public let kcal: Double?
    public let sodiumMg: Double?
    public let servingDescription: String
}

public enum OpenFoodFactsError: Error, LocalizedError {
    case notFound
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notFound: "That barcode isn't in OpenFoodFacts."
        case .badResponse: "OpenFoodFacts didn't respond as expected."
        }
    }
}

/// Minimal OpenFoodFacts v2 lookup: barcode → name, calories, sodium.
/// Prefers per-serving values; falls back to per-100 g. Converts salt to
/// sodium (salt ≈ 2.5 × sodium) when only salt is listed.
public struct OpenFoodFactsClient: Sendable {
    public init() {}

    public func product(barcode: String) async throws -> ScannedProduct {
        let fields = "product_name,brands,serving_size,nutriments"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)") else {
            throw OpenFoodFactsError.badResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Onigiri/0.1 (personal calorie tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenFoodFactsError.badResponse }
        guard http.statusCode != 404 else { throw OpenFoodFactsError.notFound }
        guard http.statusCode == 200 else { throw OpenFoodFactsError.badResponse }
        return try Self.parse(data: data, barcode: barcode)
    }

    static func parse(data: Data, barcode: String) throws -> ScannedProduct {
        let decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else {
            throw OpenFoodFactsError.notFound
        }

        var name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { name = "Scanned item \(barcode)" }
        if let brands = product.brands?.trimmingCharacters(in: .whitespacesAndNewlines),
           !brands.isEmpty,
           !name.localizedCaseInsensitiveContains(brands.components(separatedBy: ",")[0]) {
            name += " (\(brands.components(separatedBy: ",")[0]))"
        }

        let nutriments = product.nutriments

        // Sodium in grams at a given basis, converting from salt if needed.
        func sodiumGrams(_ sodium: Double?, salt: Double?) -> Double? {
            sodium ?? salt.map { $0 * 0.4 }
        }

        let kcal: Double?
        let sodiumMg: Double?
        let servingDescription: String
        if let perServing = nutriments?.energyKcalServing {
            kcal = perServing
            sodiumMg = sodiumGrams(nutriments?.sodiumServing, salt: nutriments?.saltServing)
                .map { $0 * 1000 }
            servingDescription = product.servingSize ?? "1 serving"
        } else {
            kcal = nutriments?.energyKcal100g
            sodiumMg = sodiumGrams(nutriments?.sodium100g, salt: nutriments?.salt100g)
                .map { $0 * 1000 }
            servingDescription = "per 100 g"
        }

        return ScannedProduct(
            barcode: barcode,
            name: name,
            kcal: kcal,
            sodiumMg: sodiumMg,
            servingDescription: servingDescription
        )
    }
}

// MARK: - Response models

private struct ProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let sodium100g: Double?
    let sodiumServing: Double?
    let salt100g: Double?
    let saltServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case sodium100g = "sodium_100g"
        case sodiumServing = "sodium_serving"
        case salt100g = "salt_100g"
        case saltServing = "salt_serving"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // OpenFoodFacts sometimes returns numbers as strings.
        func flexibleDouble(_ key: CodingKeys) -> Double? {
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
            return nil
        }
        energyKcal100g = flexibleDouble(.energyKcal100g)
        energyKcalServing = flexibleDouble(.energyKcalServing)
        sodium100g = flexibleDouble(.sodium100g)
        sodiumServing = flexibleDouble(.sodiumServing)
        salt100g = flexibleDouble(.salt100g)
        saltServing = flexibleDouble(.saltServing)
    }
}
