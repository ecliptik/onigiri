import Foundation

/// A product looked up by barcode, reduced to what Onigiri tracks.
public struct ScannedProduct: Sendable, Equatable {
    public let barcode: String
    public let name: String
    public let kcal: Double?
    public let sodiumMg: Double?
    public let servingDescription: String
    public let nutrients: NutrientValues

    public init(
        barcode: String,
        name: String,
        kcal: Double?,
        sodiumMg: Double?,
        servingDescription: String,
        nutrients: NutrientValues
    ) {
        self.barcode = barcode
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.servingDescription = servingDescription
        self.nutrients = nutrients
    }
}

public enum OpenFoodFactsError: Error, LocalizedError {
    case notFound
    case badResponse
    /// 429/503 — OpenFoodFacts rate-limits search (~10/min per IP) and
    /// its endpoints shed load with 503s. Waiting genuinely helps.
    case throttled

    public var errorDescription: String? {
        switch self {
        case .notFound: "That barcode isn't in OpenFoodFacts."
        case .badResponse: "OpenFoodFacts didn't respond as expected."
        case .throttled: "OpenFoodFacts is busy — wait a minute and try again."
        }
    }
}

/// Minimal OpenFoodFacts v2 lookup: barcode → name, calories, sodium.
/// Prefers per-serving values; falls back to per-100 g. Converts salt to
/// sodium (salt ≈ 2.5 × sodium) when only salt is listed.
public struct OpenFoodFactsClient: Sendable {
    public init() {}

    private static let fields = "code,product_name,brands,serving_size,nutriments"

    public func product(barcode: String) async throws -> ScannedProduct {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(Self.fields)") else {
            throw OpenFoodFactsError.badResponse
        }
        let data = try await fetch(url)
        return try Self.parse(data: data, barcode: barcode)
    }

    /// A lightweight text-search hit; full nutrition comes from a follow-up
    /// product(barcode:) call when the user picks one.
    public struct SearchResult: Sendable, Equatable, Identifiable {
        public var id: String { barcode }
        public let barcode: String
        public let name: String
        public let brand: String?

        public init(barcode: String, name: String, brand: String?) {
            self.barcode = barcode
            self.name = name
            self.brand = brand
        }
    }

    /// Free-text search of the same database — for foods without barcodes
    /// (produce, home cooking staples). Uses the CDN-backed
    /// search.openfoodfacts.org service first (the legacy cgi endpoint
    /// throttles with 503s under load), but that service has real outages
    /// (502s observed 2026-07-10) — the legacy endpoint is the fallback.
    /// Default limit of 10: each result row lazily fetches its full
    /// product for the kcal preview, so results ≈ follow-up requests
    /// against the same rate limit.
    public func search(query: String, limit: Int = 10) async throws -> [SearchResult] {
        // Three passes with exponential backoff (0s, 1s, 2s) before the
        // user sees an error — OFF's 503s are often momentary.
        var lastError: Error = OpenFoodFactsError.badResponse
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(1 << (attempt - 1))))
            }
            do {
                return try await searchOnce(query: query, limit: limit)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func searchOnce(query: String, limit: Int) async throws -> [SearchResult] {
        let primaryError: Error
        do {
            return try await searchALicious(query: query, limit: limit)
        } catch {
            primaryError = error
        }
        do {
            return try await legacySearch(query: query, limit: limit)
        } catch {
            // Both legs down. "Wait a minute" is actionable, "failed"
            // isn't — surface throttling if either leg reported it.
            if case OpenFoodFactsError.throttled = error { throw error }
            if case OpenFoodFactsError.throttled = primaryError { throw primaryError }
            throw error
        }
    }

    private func searchALicious(query: String, limit: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "page_size", value: String(limit)),
            // Rank/return fields in the user's language, not whichever
            // language edited the database last.
            .init(name: "langs", value: Self.languageCode),
        ]
        guard let url = components.url else { throw OpenFoodFactsError.badResponse }
        let data = try await fetch(url)
        return try Self.parseSearch(data: data)
    }

    private func legacySearch(query: String, limit: Int) async throws -> [SearchResult] {
        var components = URLComponents(
            string: "https://\(Self.regionSubdomain).openfoodfacts.org/cgi/search.pl"
        )!
        components.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: String(limit)),
            .init(name: "fields", value: "code,product_name,brands"),
            .init(name: "lc", value: Self.languageCode),
        ]
        guard let url = components.url else { throw OpenFoodFactsError.badResponse }
        let data = try await fetch(url)
        return try Self.parseLegacySearch(data: data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Onigiri/0.1 (personal calorie tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenFoodFactsError.badResponse }
        guard http.statusCode != 404 else { throw OpenFoodFactsError.notFound }
        guard http.statusCode != 429, http.statusCode != 503 else { throw OpenFoodFactsError.throttled }
        guard http.statusCode == 200 else { throw OpenFoodFactsError.badResponse }
        return data
    }

    /// OFF country subdomains scope search results to products sold in
    /// the user's region — without this, "roasted potatoes" surfaces
    /// whatever language edited the database last.
    private static var regionSubdomain: String {
        Locale.current.region?.identifier.lowercased() ?? "world"
    }

    private static var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static func parse(data: Data, barcode: String) throws -> ScannedProduct {
        let decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else {
            throw OpenFoodFactsError.notFound
        }
        return convert(product, barcode: barcode)
    }

    static func parseSearch(data: Data) throws -> [SearchResult] {
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.hits.compactMap { hit in
            guard let code = hit.code, !code.isEmpty,
                  let name = hit.productName ?? hit.genericName,
                  !name.isEmpty else { return nil }
            return SearchResult(barcode: code, name: name, brand: hit.brands?.first)
        }
    }

    /// The legacy CGI response: products with comma-joined brand strings.
    static func parseLegacySearch(data: Data) throws -> [SearchResult] {
        struct LegacyResponse: Decodable {
            struct LegacyProduct: Decodable {
                let code: String?
                let productName: String?
                let brands: String?

                enum CodingKeys: String, CodingKey {
                    case code, brands
                    case productName = "product_name"
                }
            }
            let products: [LegacyProduct]
        }
        let decoded = try JSONDecoder().decode(LegacyResponse.self, from: data)
        return decoded.products.compactMap { product in
            guard let code = product.code, !code.isEmpty,
                  let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let brand = product.brands?
                .split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return SearchResult(barcode: code, name: name, brand: brand)
        }
    }

    private static func convert(_ product: OFFProduct, barcode: String) -> ScannedProduct {
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
        let nutrients: NutrientValues
        // OFF reports micronutrients in grams; scale each into its
        // canonical unit (mg/µg).
        func microValues(_ grams: [String: Double]?) -> [String: Double] {
            guard let grams else { return [:] }
            var values: [String: Double] = [:]
            for micro in Micronutrient.allCases {
                if let g = grams[micro.rawValue], g > 0 {
                    values[micro.rawValue] = g * micro.unit.perGram
                }
            }
            return values
        }

        if let perServing = nutriments?.energyKcalServing {
            kcal = perServing
            sodiumMg = sodiumGrams(nutriments?.sodiumServing, salt: nutriments?.saltServing)
                .map { $0 * 1000 }
            servingDescription = product.servingSize ?? "1 serving"
            nutrients = NutrientValues(
                fatG: nutriments?.fatServing,
                saturatedFatG: nutriments?.saturatedFatServing,
                transFatG: nutriments?.transFatServing,
                polyunsaturatedFatG: nutriments?.polyunsaturatedFatServing,
                monounsaturatedFatG: nutriments?.monounsaturatedFatServing,
                cholesterolMg: nutriments?.cholesterolServing.map { $0 * 1000 },
                carbsG: nutriments?.carbsServing,
                proteinG: nutriments?.proteinsServing,
                fiberG: nutriments?.fiberServing,
                sugarG: nutriments?.sugarsServing,
                caffeineMg: nutriments?.caffeineServing.map { $0 * 1000 },
                micros: microValues(nutriments?.microsServing)
            )
        } else {
            kcal = nutriments?.energyKcal100g
            sodiumMg = sodiumGrams(nutriments?.sodium100g, salt: nutriments?.salt100g)
                .map { $0 * 1000 }
            servingDescription = "per 100 g"
            nutrients = NutrientValues(
                fatG: nutriments?.fat100g,
                saturatedFatG: nutriments?.saturatedFat100g,
                transFatG: nutriments?.transFat100g,
                polyunsaturatedFatG: nutriments?.polyunsaturatedFat100g,
                monounsaturatedFatG: nutriments?.monounsaturatedFat100g,
                cholesterolMg: nutriments?.cholesterol100g.map { $0 * 1000 },
                carbsG: nutriments?.carbs100g,
                proteinG: nutriments?.proteins100g,
                fiberG: nutriments?.fiber100g,
                sugarG: nutriments?.sugars100g,
                caffeineMg: nutriments?.caffeine100g.map { $0 * 1000 },
                micros: microValues(nutriments?.micros100g)
            )
        }

        return ScannedProduct(
            barcode: barcode,
            name: name,
            kcal: kcal,
            sodiumMg: sodiumMg,
            servingDescription: servingDescription,
            nutrients: nutrients
        )
    }
}

// MARK: - Response models

private struct ProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct SearchResponse: Decodable {
    let hits: [SearchHit]
}

private struct SearchHit: Decodable {
    let code: String?
    let productName: String?
    let genericName: String?
    let brands: [String]?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // code is usually a string but occasionally a number.
        if let text = try? container.decode(String.self, forKey: .code) {
            code = text
        } else if let number = try? container.decode(Int.self, forKey: .code) {
            code = String(number)
        } else {
            code = nil
        }
        productName = try? container.decode(String.self, forKey: .productName)
        genericName = try? container.decode(String.self, forKey: .genericName)
        // brands is an array in search-a-licious, a string in v2.
        if let list = try? container.decode([String].self, forKey: .brands) {
            brands = list
        } else if let single = try? container.decode(String.self, forKey: .brands) {
            brands = single.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            brands = nil
        }
    }
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
    let fat100g: Double?
    let fatServing: Double?
    let saturatedFat100g: Double?
    let saturatedFatServing: Double?
    let transFat100g: Double?
    let transFatServing: Double?
    let polyunsaturatedFat100g: Double?
    let polyunsaturatedFatServing: Double?
    let monounsaturatedFat100g: Double?
    let monounsaturatedFatServing: Double?
    let cholesterol100g: Double?
    let cholesterolServing: Double?
    let caffeine100g: Double?
    let caffeineServing: Double?
    let carbs100g: Double?
    let carbsServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let fiber100g: Double?
    let fiberServing: Double?
    let sugars100g: Double?
    let sugarsServing: Double?
    /// Micronutrients in grams (OFF's storage unit), keyed by
    /// Micronutrient rawValue.
    let microsServing: [String: Double]
    let micros100g: [String: Double]

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case sodium100g = "sodium_100g"
        case sodiumServing = "sodium_serving"
        case salt100g = "salt_100g"
        case saltServing = "salt_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case saturatedFat100g = "saturated-fat_100g"
        case saturatedFatServing = "saturated-fat_serving"
        case transFat100g = "trans-fat_100g"
        case transFatServing = "trans-fat_serving"
        case polyunsaturatedFat100g = "polyunsaturated-fat_100g"
        case polyunsaturatedFatServing = "polyunsaturated-fat_serving"
        case monounsaturatedFat100g = "monounsaturated-fat_100g"
        case monounsaturatedFatServing = "monounsaturated-fat_serving"
        case cholesterol100g = "cholesterol_100g"
        case cholesterolServing = "cholesterol_serving"
        case caffeine100g = "caffeine_100g"
        case caffeineServing = "caffeine_serving"
        case carbs100g = "carbohydrates_100g"
        case carbsServing = "carbohydrates_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case sugars100g = "sugars_100g"
        case sugarsServing = "sugars_serving"
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
        fat100g = flexibleDouble(.fat100g)
        fatServing = flexibleDouble(.fatServing)
        saturatedFat100g = flexibleDouble(.saturatedFat100g)
        saturatedFatServing = flexibleDouble(.saturatedFatServing)
        transFat100g = flexibleDouble(.transFat100g)
        transFatServing = flexibleDouble(.transFatServing)
        polyunsaturatedFat100g = flexibleDouble(.polyunsaturatedFat100g)
        polyunsaturatedFatServing = flexibleDouble(.polyunsaturatedFatServing)
        monounsaturatedFat100g = flexibleDouble(.monounsaturatedFat100g)
        monounsaturatedFatServing = flexibleDouble(.monounsaturatedFatServing)
        cholesterol100g = flexibleDouble(.cholesterol100g)
        cholesterolServing = flexibleDouble(.cholesterolServing)
        caffeine100g = flexibleDouble(.caffeine100g)
        caffeineServing = flexibleDouble(.caffeineServing)
        carbs100g = flexibleDouble(.carbs100g)
        carbsServing = flexibleDouble(.carbsServing)
        proteins100g = flexibleDouble(.proteins100g)
        proteinsServing = flexibleDouble(.proteinsServing)
        fiber100g = flexibleDouble(.fiber100g)
        fiberServing = flexibleDouble(.fiberServing)
        sugars100g = flexibleDouble(.sugars100g)
        sugarsServing = flexibleDouble(.sugarsServing)

        // Micronutrient keys are looked up dynamically — 24 CodingKeys
        // cases would say the same thing longer.
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)
        func flexibleDouble(named name: String) -> Double? {
            guard let key = DynamicKey(stringValue: name) else { return nil }
            if let value = try? dynamic.decode(Double.self, forKey: key) { return value }
            if let text = try? dynamic.decode(String.self, forKey: key) { return Double(text) }
            return nil
        }
        var serving: [String: Double] = [:]
        var per100: [String: Double] = [:]
        for micro in Micronutrient.allCases {
            for offID in micro.offIDs {
                if serving[micro.rawValue] == nil,
                   let value = flexibleDouble(named: "\(offID)_serving") {
                    serving[micro.rawValue] = value
                }
                if per100[micro.rawValue] == nil,
                   let value = flexibleDouble(named: "\(offID)_100g") {
                    per100[micro.rawValue] = value
                }
            }
        }
        microsServing = serving
        micros100g = per100
    }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Micronutrient {
    /// OpenFoodFacts nutriment ids to try, most common first.
    var offIDs: [String] {
        switch self {
        case .potassium: ["potassium"]
        case .calcium: ["calcium"]
        case .iron: ["iron"]
        case .magnesium: ["magnesium"]
        case .zinc: ["zinc"]
        case .phosphorus: ["phosphorus"]
        case .selenium: ["selenium"]
        case .copper: ["copper"]
        case .manganese: ["manganese"]
        case .iodine: ["iodine"]
        case .chromium: ["chromium"]
        case .molybdenum: ["molybdenum"]
        case .chloride: ["chloride"]
        case .vitaminA: ["vitamin-a"]
        case .vitaminC: ["vitamin-c"]
        case .vitaminD: ["vitamin-d"]
        case .vitaminE: ["vitamin-e"]
        case .vitaminB6: ["vitamin-b6"]
        case .vitaminB12: ["vitamin-b12"]
        case .folate: ["folates", "vitamin-b9"]
        case .vitaminK: ["vitamin-k"]
        case .thiamin: ["vitamin-b1"]
        case .riboflavin: ["vitamin-b2"]
        case .niacin: ["vitamin-pp", "vitamin-b3"]
        case .pantothenicAcid: ["pantothenic-acid", "vitamin-b5"]
        case .biotin: ["biotin", "vitamin-b7"]
        }
    }
}
