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
    /// 429 — OpenFoodFacts rate-limits search (~10/min per IP). Retrying
    /// inside the backoff window can't succeed; only waiting helps.
    case throttled
    /// 503 — the endpoints shed load momentarily; a short retry often
    /// recovers (distinct from .throttled, which must fail fast).
    case serverBusy

    public var errorDescription: String? {
        switch self {
        case .notFound: "That barcode isn't in OpenFoodFacts."
        case .badResponse: "OpenFoodFacts didn't respond as expected."
        case .throttled, .serverBusy: "OpenFoodFacts is busy — wait a minute and try again."
        }
    }

    /// Both flavors of "busy" for user-facing messaging.
    public var isBusy: Bool {
        switch self {
        case .throttled, .serverBusy: true
        default: false
        }
    }
}

/// Process-wide barcode → product cache. Product data barely changes;
/// re-searching the same lunch words (or re-scanning a barcode a search
/// row already fetched) used to re-spend OFF's ~10/min rate limit on
/// every sheet presentation. Bounded FIFO; successful lookups only.
private actor ProductCache {
    static let shared = ProductCache()
    private var products: [String: ScannedProduct] = [:]
    private var order: [String] = []
    private let limit = 200

    func product(for barcode: String) -> ScannedProduct? {
        products[barcode]
    }

    func store(_ product: ScannedProduct, for barcode: String) {
        if products.updateValue(product, forKey: barcode) == nil {
            order.append(barcode)
        }
        while order.count > limit {
            products.removeValue(forKey: order.removeFirst())
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
        if let cached = await ProductCache.shared.product(for: barcode) {
            return cached
        }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(Self.fields)") else {
            throw OpenFoodFactsError.badResponse
        }
        let data = try await fetch(url)
        let product = try Self.parse(data: data, barcode: barcode)
        await ProductCache.shared.store(product, for: barcode)
        return product
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
    /// against the same rate limit. Pages start at 1; callers fetch the
    /// next page when the user scrolls past the last row.
    public func search(query: String, limit: Int = 10, page: Int = 1) async throws -> [SearchResult] {
        // Three passes with exponential backoff (0s, 1s, 2s) before the
        // user sees an error — OFF's 503s (.serverBusy) are often
        // momentary and stay retryable. Rate limiting and cancellation
        // fail fast: a 429 can't clear inside the backoff window
        // (retrying digs the rate-limit hole deeper), and a superseded
        // search must stop making requests, not retry them.
        var lastError: Error = OpenFoodFactsError.badResponse
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(1 << (attempt - 1))))
            }
            do {
                return try await searchOnce(query: query, limit: limit, page: page)
            } catch {
                if case OpenFoodFactsError.throttled = error { throw error }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                lastError = error
            }
        }
        throw lastError
    }

    /// Both endpoints match loosely ("roasted potatoes" surfaces "honey
    /// roasted oats") and order by scan-count popularity, so results
    /// re-rank client-side for user intent: whole-phrase matches first,
    /// then an exact-name bonus (a product NAMED your query is your
    /// query), then per-word matches — plural-insensitive, so "grapes"
    /// credits "Grape" — minus a small penalty per name word you never
    /// asked for ("Grapes" beats "Grape Jelly" beats "Grape Seed Oil").
    /// Brand words count at half the name weight ("Kirkland",
    /// "McDonald's"), so food words in the name still dominate. Server
    /// order breaks ties.
    static func rank(_ results: [SearchResult], query: String) -> [SearchResult] {
        let phrase = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = tokenize(phrase)
        guard !words.isEmpty else { return results }
        func score(_ result: SearchResult) -> Int {
            let name = result.name.lowercased()
            let brand = result.brand?.lowercased() ?? ""
            let nameTokens = tokenize(name)
            let brandTokens = tokenize(brand)
            var matchedInName = 0
            var matchedInBrand = 0
            for word in words {
                if nameTokens.contains(where: { formsMatch(word, $0) }) {
                    matchedInName += 1
                } else if brandTokens.contains(where: { formsMatch(word, $0) }) {
                    matchedInBrand += 1
                }
            }
            var value = matchedInName * 10 + matchedInBrand * 5
            // "I typed a food, not a product": every name word the query
            // didn't ask for is a step away from intent. Capped so long
            // descriptive names aren't buried outright.
            let extraTokens = nameTokens.count { token in
                !words.contains { formsMatch($0, token) }
            }
            value -= min(extraTokens, 3) * 2
            // The name IS the query, up to word order and plurals.
            if matchedInName == words.count, extraTokens == 0 {
                value += 50
            }
            if name.contains(phrase) {
                value += 100
            } else if brand.contains(phrase) {
                value += 40
            }
            return value
        }
        return results.enumerated()
            .map { (offset: $0.offset, result: $0.element, score: score($0.element)) }
            .sorted {
                $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset
            }
            .map(\.result)
    }

    /// Lowercased alphanumeric words, single letters dropped ("McDonald's"
    /// → ["mcdonald"], not a stray "s").
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// Plural-insensitive word comparison: two words match when any of
    /// their singular/plural forms coincide — "grapes" ↔ "grape",
    /// "tomatoes" ↔ "tomato", "berries" ↔ "berry".
    static func formsMatch(_ lhs: String, _ rhs: String) -> Bool {
        !wordForms(lhs).isDisjoint(with: wordForms(rhs))
    }

    private static func wordForms(_ word: String) -> Set<String> {
        var forms: Set<String> = [word]
        if word.hasSuffix("ies"), word.count > 4 {
            forms.insert(String(word.dropLast(3)) + "y")
        }
        if word.hasSuffix("es"), word.count > 4 {
            forms.insert(String(word.dropLast(2)))
        }
        if word.hasSuffix("s"), word.count > 3 {
            forms.insert(String(word.dropLast()))
        }
        return forms
    }

    private func searchOnce(query: String, limit: Int, page: Int) async throws -> [SearchResult] {
        let primaryError: Error
        do {
            return try await Self.rank(searchALicious(query: query, limit: limit, page: page), query: query)
        } catch {
            primaryError = error
        }
        do {
            return try await Self.rank(legacySearch(query: query, limit: limit, page: page), query: query)
        } catch {
            // Both legs down. "Wait a minute" is actionable, "failed"
            // isn't — surface busyness if either leg reported it.
            if (error as? OpenFoodFactsError)?.isBusy == true { throw error }
            if (primaryError as? OpenFoodFactsError)?.isBusy == true { throw primaryError }
            throw error
        }
    }

    private func searchALicious(query: String, limit: Int, page: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "page_size", value: String(limit)),
            .init(name: "page", value: String(page)),
            // Rank/return fields in the user's language, not whichever
            // language edited the database last.
            .init(name: "langs", value: Self.languageCode),
        ]
        guard let url = components.url else { throw OpenFoodFactsError.badResponse }
        let data = try await fetch(url)
        return try Self.parseSearch(data: data)
    }

    private func legacySearch(query: String, limit: Int, page: Int) async throws -> [SearchResult] {
        var components = URLComponents(
            string: "https://\(Self.regionSubdomain).openfoodfacts.org/cgi/search.pl"
        )!
        components.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: String(limit)),
            .init(name: "page", value: String(page)),
            .init(name: "fields", value: "code,product_name,brands"),
            .init(name: "lc", value: Self.languageCode),
            // Only products with filled nutrition facts: entries without
            // them (common for raw produce) are unloggable anyway — the
            // client weeds them after a wasted per-row fetch — and they
            // crowd loggable results out of the page. Verified live
            // 2026-07-13 (count drops, results all complete). NOT applied
            // to search-a-licious: its filter syntax couldn't be verified
            // (the service was mid-outage), and a wrong filter there
            // would 200-with-zero-hits — which never triggers this
            // fallback and would break search outright.
            .init(name: "tagtype_0", value: "states"),
            .init(name: "tag_contains_0", value: "contains"),
            .init(name: "tag_0", value: "en:nutrition-facts-completed"),
        ]
        guard let url = components.url else { throw OpenFoodFactsError.badResponse }
        let data = try await fetch(url)
        return try Self.parseLegacySearch(data: data)
    }

    /// Interactive-search session: the default 60 s request timeout ×
    /// retries × two endpoints could hold the radio for minutes on a dead
    /// path; 15 s is generous for these small JSON responses.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Onigiri/0.1 (personal calorie tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenFoodFactsError.badResponse }
        guard http.statusCode != 404 else { throw OpenFoodFactsError.notFound }
        guard http.statusCode != 429 else { throw OpenFoodFactsError.throttled }
        guard http.statusCode != 503 else { throw OpenFoodFactsError.serverBusy }
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
        // OpenFoodFacts sometimes returns numbers as strings. Probe with
        // contains() first — most keys are absent, and each blind decode
        // attempt materialized a thrown DecodingError with context.
        func flexibleDouble(_ key: CodingKeys) -> Double? {
            guard container.contains(key) else { return nil }
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
        // ~28 OFF ids × 2 bases probed per product — check presence
        // against the actual key set instead of decode-and-catch.
        let presentKeys = Set(dynamic.allKeys.map(\.stringValue))
        func flexibleDouble(named name: String) -> Double? {
            guard presentKeys.contains(name), let key = DynamicKey(stringValue: name) else { return nil }
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
