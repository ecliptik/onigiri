import Foundation

/// A generic food from USDA FoodData Central. Unlike OFF's search index,
/// FDC search responses embed the full per-100 g nutrient table — a row
/// needs no follow-up fetch to show calories.
public struct GenericFood: Sendable, Equatable, Identifiable {
    public let fdcId: Int
    public let description: String
    /// Source dataset ("Foundation", "SR Legacy", "Survey (FNDDS)") —
    /// rides the row's brand/caption slot.
    public let dataType: String
    public let kcalPer100g: Double?
    public let sodiumMgPer100g: Double?
    public let nutrientsPer100g: NutrientValues

    public var id: Int { fdcId }

    /// The row-model product: FDC search rows arrive with nutrients
    /// inline, so this stands in for OFF's lazily fetched detail. The
    /// serving copy matches OFF's per-100 g fallback.
    public var per100gProduct: ScannedProduct {
        ScannedProduct(
            barcode: FoodDataCentralClient.code(for: fdcId),
            name: description,
            kcal: kcalPer100g,
            sodiumMg: sodiumMgPer100g,
            servingDescription: "per 100 g",
            nutrients: nutrientsPer100g
        )
    }

    public init(
        fdcId: Int,
        description: String,
        dataType: String,
        kcalPer100g: Double?,
        sodiumMgPer100g: Double?,
        nutrientsPer100g: NutrientValues
    ) {
        self.fdcId = fdcId
        self.description = description
        self.dataType = dataType
        self.kcalPer100g = kcalPer100g
        self.sodiumMgPer100g = sodiumMgPer100g
        self.nutrientsPer100g = nutrientsPer100g
    }
}

/// A household measure with its gram weight ("1 cup" = 151 g), from the
/// food-detail endpoint — fetched once on pick to build the serving
/// description and per-serving values.
public struct FoodPortion: Sendable, Equatable {
    public let description: String
    public let gramWeight: Double

    public init(description: String, gramWeight: Double) {
        self.description = description
        self.gramWeight = gramWeight
    }
}

public enum FoodDataCentralError: Error, LocalizedError {
    case notFound
    case badResponse
    /// 403 — api.data.gov rejects the key (invalid or revoked). Distinct,
    /// actionable copy: the fix is in Settings, not retrying.
    case badAPIKey
    /// 429 — the key's hourly quota is spent; only waiting helps.
    case throttled
    /// 5xx — momentary shedding; a short retry often recovers.
    case serverBusy

    // "FDC" throughout: the one long form ("USDA FoodData Central") lives
    // in Settings, which introduces the acronym — everywhere else uses it.
    public var errorDescription: String? {
        switch self {
        case .notFound: "That food isn't in FDC."
        case .badResponse: "FDC didn't respond as expected."
        case .badAPIKey: "FDC rejected the API key — check it in Settings."
        case .throttled, .serverBusy: "FDC is busy — wait a minute and try again."
        }
    }

    /// Both flavors of "busy" for user-facing messaging (same contract as
    /// OpenFoodFactsError.isBusy).
    public var isBusy: Bool {
        switch self {
        case .throttled, .serverBusy: true
        default: false
        }
    }
}

/// USDA FoodData Central text search — the canonical generic-foods
/// database ("Grapes, red or green, raw" with lab nutrients), complement
/// to OpenFoodFacts' barcode data. Requires a user-supplied api.data.gov
/// key (1,000 requests/hour free tier).
public struct FoodDataCentralClient: Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// The generic datasets. Branded is excluded on purpose: it's US-only
    /// GS1 data and barcode scanning is OFF's job.
    static let dataTypes = ["Foundation", "SR Legacy", "Survey (FNDDS)"]

    /// Free-text search, results re-ranked with the shared intent scoring
    /// (FDC has its own relevance quirks: live probe put "Grape leaves,
    /// canned" above raw grapes). Pages start at 1.
    public func search(query: String, limit: Int = 30, page: Int = 1) async throws -> [GenericFood] {
        // Same retry contract as OFF search: three passes with backoff for
        // momentary 5xx; throttling, a bad key, and cancellation fail fast
        // (retrying can't fix any of them).
        var lastError: Error = FoodDataCentralError.badResponse
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(1 << (attempt - 1))))
            }
            do {
                return try await searchOnce(query: query, limit: limit, page: page)
            } catch {
                if let fdcError = error as? FoodDataCentralError,
                   fdcError == .throttled || fdcError == .badAPIKey {
                    throw error
                }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                lastError = error
            }
        }
        throw lastError
    }

    private func searchOnce(query: String, limit: Int, page: Int) async throws -> [GenericFood] {
        // POST with a JSON body, not GET: the gateway 400s any request
        // whose query string contains the "Survey (FNDDS)" parentheses,
        // encoded or literal (verified live 2026-07-13).
        guard var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search") else {
            throw FoodDataCentralError.badResponse
        }
        components.queryItems = [.init(name: "api_key", value: apiKey)]
        guard let url = components.url else { throw FoodDataCentralError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SearchCriteria(
            query: query,
            dataType: Self.dataTypes,
            pageSize: limit,
            pageNumber: page
        ))
        let data = try await fetch(request)
        let hits = try Self.parseSearch(data: data)
        return OpenFoodFactsClient.rank(hits, query: query, name: \.description, brand: { _ in nil })
    }

    /// One minimal search round-trip (pageSize 1) proving the key works —
    /// Settings' "Test Key" button, so a bad key surfaces at entry time
    /// instead of mid-search. Single attempt, fail fast: a test button
    /// answering in one beat beats a 3×-backoff retry ladder.
    public func validateKey() async throws {
        _ = try await searchOnce(query: "apple", limit: 1, page: 1)
    }

    /// The row-model code an FDC food travels under in the barcode slot —
    /// identity for caching and (harmlessly) for the library's barcode
    /// field; a scanned EAN can never collide with it.
    public static func code(for fdcId: Int) -> String { "fdc:\(fdcId)" }

    public static func fdcId(fromCode code: String) -> Int? {
        code.hasPrefix("fdc:") ? Int(code.dropFirst(4)) : nil
    }

    /// The pick-path product: the per-100 g search hit upgraded to the
    /// food's best household measure ("1 cup, seedless (151 g)"), cached
    /// process-wide like OFF barcode lookups. A failed portions fetch
    /// falls back to the per-100 g values — real data beats an error.
    public func pickedProduct(for base: ScannedProduct) async -> ScannedProduct {
        guard let fdcId = Self.fdcId(fromCode: base.barcode) else { return base }
        if let cached = await ProductCache.shared.product(for: base.barcode) {
            return cached
        }
        guard let portions = try? await portions(fdcId: fdcId) else { return base }
        let product = Self.scaled(base, to: Self.bestPortion(portions))
        await ProductCache.shared.store(product, for: base.barcode)
        return product
    }

    /// The prefill serving: the household measure nearest a 100 g
    /// serving. Sequence order can't be trusted for this — FNDDS lists
    /// the single fruit first ("1 grape", 7 g; verified live), which is
    /// a counting unit, not a serving.
    static func bestPortion(_ portions: [FoodPortion]) -> FoodPortion? {
        portions.min {
            abs($0.gramWeight - 100) < abs($1.gramWeight - 100)
        }
    }

    /// Per-100 g values rescaled to a household portion; no portion means
    /// the per-100 g product stands as-is.
    static func scaled(_ base: ScannedProduct, to portion: FoodPortion?) -> ScannedProduct {
        guard let portion, portion.gramWeight > 0 else { return base }
        let factor = portion.gramWeight / 100
        let grams = portion.gramWeight.formatted(.number.precision(.fractionLength(0...1)))
        return ScannedProduct(
            barcode: base.barcode,
            name: base.name,
            kcal: base.kcal.map { $0 * factor },
            sodiumMg: base.sodiumMg.map { $0 * factor },
            servingDescription: "\(portion.description) (\(grams) g)",
            nutrients: base.nutrients.scaled(by: factor)
        )
    }

    /// The food's household portions, best first — fetched once when the
    /// user picks a search row.
    public func portions(fdcId: Int) async throws -> [FoodPortion] {
        guard var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcId)") else {
            throw FoodDataCentralError.badResponse
        }
        components.queryItems = [.init(name: "api_key", value: apiKey)]
        guard let url = components.url else { throw FoodDataCentralError.badResponse }
        let data = try await fetch(URLRequest(url: url))
        return try Self.parsePortions(data: data)
    }

    /// Interactive-search session, same rationale as OFF's: 15 s beats the
    /// 60 s default for small JSON responses on a dead path.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private func fetch(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Onigiri/0.1 (personal calorie tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FoodDataCentralError.badResponse }
        switch http.statusCode {
        case 200: return data
        case 403: throw FoodDataCentralError.badAPIKey
        case 404: throw FoodDataCentralError.notFound
        case 429: throw FoodDataCentralError.throttled
        case 500...599: throw FoodDataCentralError.serverBusy
        default: throw FoodDataCentralError.badResponse
        }
    }

    // MARK: - Parsing

    static func parseSearch(data: Data) throws -> [GenericFood] {
        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw FoodDataCentralError.badResponse
        }
        return decoded.foods.compactMap { food in
            guard let description = food.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !description.isEmpty else { return nil }
            let mapped = convert(food.foodNutrients ?? [])
            return GenericFood(
                fdcId: food.fdcId,
                description: description,
                dataType: food.dataType ?? "",
                kcalPer100g: mapped.kcal,
                sodiumMgPer100g: mapped.sodiumMg,
                nutrientsPer100g: mapped.values
            )
        }
    }

    /// Portions from the detail response. The shape varies by dataset:
    /// Survey (FNDDS) fills `portionDescription` ("1 cup"); SR Legacy and
    /// Foundation give `amount` + `modifier`/`measureUnit`. Order follows
    /// `sequenceNumber` (FDC lists the common measure first).
    static func parsePortions(data: Data) throws -> [FoodPortion] {
        let decoded: FoodDetail
        do {
            decoded = try JSONDecoder().decode(FoodDetail.self, from: data)
        } catch {
            throw FoodDataCentralError.badResponse
        }
        let portions = (decoded.foodPortions ?? [])
            .sorted { ($0.sequenceNumber ?? .max) < ($1.sequenceNumber ?? .max) }
        return portions.compactMap { portion in
            guard let grams = portion.gramWeight, grams > 0,
                  let description = portion.displayDescription else { return nil }
            return FoodPortion(description: description, gramWeight: grams)
        }
    }

    /// FDC nutrient numbers → Onigiri fields, from the live probe's
    /// nutrient table (2026-07-13). Energy appears in both KCAL (208) and
    /// kJ (268) — only 208 KCAL counts. Values arrive in each nutrient's
    /// own unit (G/MG/UG); everything funnels through grams into the
    /// field's canonical unit. Iodine, chromium, molybdenum, chloride,
    /// and biotin stay unmapped: their numbers never appeared in verified
    /// responses, and a wrong number would silently file another
    /// nutrient's value under theirs.
    static func convert(_ nutrients: [SearchResponse.Food.Nutrient]) -> (
        kcal: Double?, sodiumMg: Double?, values: NutrientValues
    ) {
        var kcal: Double?
        var sodiumMg: Double?
        var values = NutrientValues()
        // "Folate, DFE" (435) is the label value; "Folate, total" (417) is
        // the fallback when a dataset omits DFE.
        var folateTotal: Double?

        func grams(_ value: Double, unitName: String?) -> Double? {
            switch unitName?.uppercased() {
            case "G": value
            case "MG": value / 1_000
            case "UG", "µG", "MCG": value / 1_000_000
            default: nil // IU, kJ — unmapped by design
            }
        }

        for nutrient in nutrients {
            guard let number = nutrient.nutrientNumber, let value = nutrient.value else { continue }
            if number == "208" {
                if nutrient.unitName?.uppercased() == "KCAL" { kcal = value }
                continue
            }
            guard let g = grams(value, unitName: nutrient.unitName) else { continue }
            switch number {
            case "307": sodiumMg = g * 1_000
            case "203": values.proteinG = g
            case "204": values.fatG = g
            case "205": values.carbsG = g
            case "269": values.sugarG = g
            case "291": values.fiberG = g
            case "606": values.saturatedFatG = g
            case "605": values.transFatG = g
            case "645": values.monounsaturatedFatG = g
            case "646": values.polyunsaturatedFatG = g
            case "601": values.cholesterolMg = g * 1_000
            case "262": values.caffeineMg = g * 1_000
            default:
                guard g > 0 else { continue } // zero micros are noise, as in OFF
                switch number {
                case "301": values[.calcium] = g * Micronutrient.calcium.unit.perGram
                case "303": values[.iron] = g * Micronutrient.iron.unit.perGram
                case "304": values[.magnesium] = g * Micronutrient.magnesium.unit.perGram
                case "305": values[.phosphorus] = g * Micronutrient.phosphorus.unit.perGram
                case "306": values[.potassium] = g * Micronutrient.potassium.unit.perGram
                case "309": values[.zinc] = g * Micronutrient.zinc.unit.perGram
                case "312": values[.copper] = g * Micronutrient.copper.unit.perGram
                case "315": values[.manganese] = g * Micronutrient.manganese.unit.perGram
                case "317": values[.selenium] = g * Micronutrient.selenium.unit.perGram
                case "320": values[.vitaminA] = g * Micronutrient.vitaminA.unit.perGram
                case "323": values[.vitaminE] = g * Micronutrient.vitaminE.unit.perGram
                case "328": values[.vitaminD] = g * Micronutrient.vitaminD.unit.perGram
                case "401": values[.vitaminC] = g * Micronutrient.vitaminC.unit.perGram
                case "404": values[.thiamin] = g * Micronutrient.thiamin.unit.perGram
                case "405": values[.riboflavin] = g * Micronutrient.riboflavin.unit.perGram
                case "406": values[.niacin] = g * Micronutrient.niacin.unit.perGram
                case "410": values[.pantothenicAcid] = g * Micronutrient.pantothenicAcid.unit.perGram
                case "415": values[.vitaminB6] = g * Micronutrient.vitaminB6.unit.perGram
                case "418": values[.vitaminB12] = g * Micronutrient.vitaminB12.unit.perGram
                case "430": values[.vitaminK] = g * Micronutrient.vitaminK.unit.perGram
                case "435": values[.folate] = g * Micronutrient.folate.unit.perGram
                case "417": folateTotal = g * Micronutrient.folate.unit.perGram
                default: break
                }
            }
        }
        if values[.folate] == nil, let folateTotal { values[.folate] = folateTotal }
        return (kcal, sodiumMg, values)
    }

    // MARK: - Request/response models

    private struct SearchCriteria: Encodable {
        let query: String
        let dataType: [String]
        let pageSize: Int
        let pageNumber: Int
    }

    struct SearchResponse: Decodable {
        struct Food: Decodable {
            struct Nutrient: Decodable {
                let nutrientNumber: String?
                let unitName: String?
                let value: Double?
            }

            let fdcId: Int
            let description: String?
            let dataType: String?
            let foodNutrients: [Nutrient]?
        }

        let foods: [Food]
    }

    struct FoodDetail: Decodable {
        struct Portion: Decodable {
            struct MeasureUnit: Decodable {
                let name: String?
            }

            let amount: Double?
            let modifier: String?
            let portionDescription: String?
            let measureUnit: MeasureUnit?
            let gramWeight: Double?
            let sequenceNumber: Int?

            /// "1 cup" from whichever fields the dataset filled — all
            /// three shapes verified live 2026-07-13. FNDDS fills
            /// `portionDescription` (unusable rows say "Quantity not
            /// specified") and its `modifier` is a numeric portion CODE
            /// ("10205"), never words; SR Legacy uses a word `modifier`
            /// ("grape"); Foundation a `measureUnit` whose placeholder
            /// name is "undetermined" and whose real name can be the
            /// regulatory "RACC" — rendered as the plain word "serving".
            var displayDescription: String? {
                if let text = portionDescription?.trimmingCharacters(in: .whitespaces),
                   !text.isEmpty {
                    return text.localizedCaseInsensitiveContains("not specified") ? nil : text
                }
                var unit = [measureUnit?.name, modifier]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .filter {
                        !$0.isEmpty && $0.lowercased() != "undetermined"
                            && !$0.allSatisfy(\.isNumber)
                    }
                    .first
                if unit?.uppercased() == "RACC" { unit = "serving" }
                guard let unit else { return nil }
                guard let amount, amount > 0 else { return unit }
                let count = amount.formatted(.number.precision(.fractionLength(0...2)))
                return "\(count) \(unit)"
            }
        }

        let foodPortions: [Portion]?
    }
}
