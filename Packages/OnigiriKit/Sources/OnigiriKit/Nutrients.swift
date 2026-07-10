import Foundation

/// Meal-slot categories for organizing the food library and the daily log.
public enum FoodCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    public var id: String { rawValue }

    /// The meal slot a moment of the day falls into: breakfast 5–11 AM,
    /// lunch 11 AM–3 PM, snack 3–6 PM, dinner 6–11 PM. Late night
    /// (11 PM–5 AM) counts as a snack.
    public static func slot(for date: Date, calendar: Calendar = .current) -> FoodCategory {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<15: .lunch
        case 15..<18: .snack
        case 18..<23: .dinner
        default: .snack
        }
    }
}

/// The vitamin/mineral set Onigiri tracks — the ones OpenFoodFacts usually
/// carries and Apple Health accepts. Each value is stored in the nutrient's
/// canonical unit (`unit`), matching how nutrition labels state it.
public enum Micronutrient: String, CaseIterable, Codable, Sendable, Identifiable {
    // Declaration order is display order: minerals, then vitamins.
    case potassium, calcium, iron, magnesium, zinc
    case phosphorus, selenium, copper, manganese, iodine, chromium, molybdenum, chloride
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminB6, vitaminB12, folate
    case vitaminK, thiamin, riboflavin, niacin, pantothenicAcid, biotin

    public var id: String { rawValue }

    /// Display groups, in declaration (= display) order.
    public static let minerals: [Micronutrient] = [
        .potassium, .calcium, .iron, .magnesium, .zinc,
        .phosphorus, .selenium, .copper, .manganese, .iodine,
        .chromium, .molybdenum, .chloride,
    ]
    public static let vitamins: [Micronutrient] = [
        .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminB6, .vitaminB12,
        .folate, .vitaminK, .thiamin, .riboflavin, .niacin,
        .pantothenicAcid, .biotin,
    ]

    public var displayName: String {
        switch self {
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .zinc: "Zinc"
        case .phosphorus: "Phosphorus"
        case .selenium: "Selenium"
        case .copper: "Copper"
        case .manganese: "Manganese"
        case .iodine: "Iodine"
        case .chromium: "Chromium"
        case .molybdenum: "Molybdenum"
        case .chloride: "Chloride"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminB6: "Vitamin B6"
        case .vitaminB12: "Vitamin B12"
        case .folate: "Folate"
        case .vitaminK: "Vitamin K"
        case .thiamin: "Thiamin (B1)"
        case .riboflavin: "Riboflavin (B2)"
        case .niacin: "Niacin (B3)"
        case .pantothenicAcid: "Pantothenic acid (B5)"
        case .biotin: "Biotin (B7)"
        }
    }

    /// Canonical storage/display unit, following label convention (and
    /// Health's): µg for the trace nutrients, mg for the rest.
    public var unit: MicronutrientUnit {
        switch self {
        case .vitaminA, .vitaminD, .vitaminB12, .folate,
             .vitaminK, .biotin, .selenium, .iodine, .chromium, .molybdenum:
            .micrograms
        default:
            .milligrams
        }
    }
}

public enum MicronutrientUnit: Sendable {
    case milligrams, micrograms

    public var symbol: String {
        switch self {
        case .milligrams: "mg"
        case .micrograms: "µg"
        }
    }

    /// OpenFoodFacts reports nutriments in grams; scale into this unit.
    public var perGram: Double {
        switch self {
        case .milligrams: 1_000
        case .micrograms: 1_000_000
        }
    }
}

/// Optional extended nutrients. Calories and sodium remain the first-class
/// fields; macros (grams), cholesterol (mg), and micronutrients ride along
/// when known. Trans fat is app-only: Apple Health has no dietary type
/// for it.
public struct NutrientValues: Sendable, Equatable, Hashable, Codable {
    public var fatG: Double?
    public var saturatedFatG: Double?
    public var transFatG: Double?
    public var polyunsaturatedFatG: Double?
    public var monounsaturatedFatG: Double?
    public var cholesterolMg: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fiberG: Double?
    public var sugarG: Double?
    public var caffeineMg: Double?
    /// Micronutrients in their canonical units, keyed by Micronutrient
    /// rawValue — a plain-string dictionary so old encodings decode and
    /// keys from newer app versions survive a round trip.
    public var micros: [String: Double]

    public init(
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        transFatG: Double? = nil,
        polyunsaturatedFatG: Double? = nil,
        monounsaturatedFatG: Double? = nil,
        cholesterolMg: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        caffeineMg: Double? = nil,
        micros: [String: Double] = [:]
    ) {
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.transFatG = transFatG
        self.polyunsaturatedFatG = polyunsaturatedFatG
        self.monounsaturatedFatG = monounsaturatedFatG
        self.cholesterolMg = cholesterolMg
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.caffeineMg = caffeineMg
        self.micros = micros
    }

    public subscript(_ micro: Micronutrient) -> Double? {
        get { micros[micro.rawValue] }
        set { micros[micro.rawValue] = newValue }
    }

    /// Every optional scalar field, paired with its coding key — one list
    /// to keep isEmpty/scaled/+/Codable in lockstep as fields accrue.
    /// Computed because key paths aren't Sendable, so a stored static
    /// would trip strict concurrency.
    private static var scalarFields: [(WritableKeyPath<NutrientValues, Double?>, CodingKeys)] { [
        (\.fatG, .fatG),
        (\.saturatedFatG, .saturatedFatG),
        (\.transFatG, .transFatG),
        (\.polyunsaturatedFatG, .polyunsaturatedFatG),
        (\.monounsaturatedFatG, .monounsaturatedFatG),
        (\.cholesterolMg, .cholesterolMg),
        (\.carbsG, .carbsG),
        (\.proteinG, .proteinG),
        (\.fiberG, .fiberG),
        (\.sugarG, .sugarG),
        (\.caffeineMg, .caffeineMg),
    ] }

    public var isEmpty: Bool {
        Self.scalarFields.allSatisfy { self[keyPath: $0.0] == nil } && micros.isEmpty
    }

    public func scaled(by factor: Double) -> NutrientValues {
        var scaled = self
        for (field, _) in Self.scalarFields {
            scaled[keyPath: field] = self[keyPath: field].map { $0 * factor }
        }
        scaled.micros = micros.mapValues { $0 * factor }
        return scaled
    }

    /// Sums fields where at least one side has a value.
    public static func + (lhs: NutrientValues, rhs: NutrientValues) -> NutrientValues {
        var sum = lhs
        for (field, _) in scalarFields {
            switch (lhs[keyPath: field], rhs[keyPath: field]) {
            case (nil, nil): sum[keyPath: field] = nil
            case let (a, b): sum[keyPath: field] = (a ?? 0) + (b ?? 0)
            }
        }
        sum.micros = lhs.micros.merging(rhs.micros, uniquingKeysWith: +)
        return sum
    }

    // Hand-written Codable: every field is decodeIfPresent so encodings
    // from before each field's addition still decode.
    private enum CodingKeys: String, CodingKey {
        case fatG, saturatedFatG, transFatG, polyunsaturatedFatG, monounsaturatedFatG
        case cholesterolMg, carbsG, proteinG, fiberG, sugarG, caffeineMg, micros
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // micros first: the keypath writes below need self fully
        // initialized (the optionals default to nil).
        micros = try container.decodeIfPresent([String: Double].self, forKey: .micros) ?? [:]
        for (field, key) in Self.scalarFields {
            self[keyPath: field] = try container.decodeIfPresent(Double.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (field, key) in Self.scalarFields {
            try container.encodeIfPresent(self[keyPath: field], forKey: key)
        }
        if !micros.isEmpty {
            try container.encode(micros, forKey: .micros)
        }
    }
}
