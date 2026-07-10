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
    case potassium, calcium, iron, magnesium, zinc
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminB6, vitaminB12, folate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .zinc: "Zinc"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminB6: "Vitamin B6"
        case .vitaminB12: "Vitamin B12"
        case .folate: "Folate"
        }
    }

    /// Canonical storage/display unit: mg for the minerals and vitamins
    /// C/E/B6, µg for A/D/B12/folate (label convention and Health's).
    public var unit: MicronutrientUnit {
        switch self {
        case .vitaminA, .vitaminD, .vitaminB12, .folate: .micrograms
        default: .milligrams
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
public struct NutrientValues: Sendable, Equatable, Codable {
    public var fatG: Double?
    public var saturatedFatG: Double?
    public var transFatG: Double?
    public var cholesterolMg: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fiberG: Double?
    public var sugarG: Double?
    /// Micronutrients in their canonical units, keyed by Micronutrient
    /// rawValue — a plain-string dictionary so old encodings decode and
    /// keys from newer app versions survive a round trip.
    public var micros: [String: Double]

    public init(
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        transFatG: Double? = nil,
        cholesterolMg: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        micros: [String: Double] = [:]
    ) {
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.transFatG = transFatG
        self.cholesterolMg = cholesterolMg
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.micros = micros
    }

    public subscript(_ micro: Micronutrient) -> Double? {
        get { micros[micro.rawValue] }
        set { micros[micro.rawValue] = newValue }
    }

    public var isEmpty: Bool {
        fatG == nil && saturatedFatG == nil && transFatG == nil && cholesterolMg == nil
            && carbsG == nil && proteinG == nil && fiberG == nil && sugarG == nil
            && micros.isEmpty
    }

    public func scaled(by factor: Double) -> NutrientValues {
        NutrientValues(
            fatG: fatG.map { $0 * factor },
            saturatedFatG: saturatedFatG.map { $0 * factor },
            transFatG: transFatG.map { $0 * factor },
            cholesterolMg: cholesterolMg.map { $0 * factor },
            carbsG: carbsG.map { $0 * factor },
            proteinG: proteinG.map { $0 * factor },
            fiberG: fiberG.map { $0 * factor },
            sugarG: sugarG.map { $0 * factor },
            micros: micros.mapValues { $0 * factor }
        )
    }

    /// Sums fields where at least one side has a value.
    public static func + (lhs: NutrientValues, rhs: NutrientValues) -> NutrientValues {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case (nil, nil): nil
            default: (a ?? 0) + (b ?? 0)
            }
        }
        return NutrientValues(
            fatG: add(lhs.fatG, rhs.fatG),
            saturatedFatG: add(lhs.saturatedFatG, rhs.saturatedFatG),
            transFatG: add(lhs.transFatG, rhs.transFatG),
            cholesterolMg: add(lhs.cholesterolMg, rhs.cholesterolMg),
            carbsG: add(lhs.carbsG, rhs.carbsG),
            proteinG: add(lhs.proteinG, rhs.proteinG),
            fiberG: add(lhs.fiberG, rhs.fiberG),
            sugarG: add(lhs.sugarG, rhs.sugarG),
            micros: lhs.micros.merging(rhs.micros, uniquingKeysWith: +)
        )
    }

    // Hand-written Codable: every field is decodeIfPresent so encodings
    // from before each addition (micros, saturated/trans fat, cholesterol)
    // still decode.
    private enum CodingKeys: String, CodingKey {
        case fatG, saturatedFatG, transFatG, cholesterolMg
        case carbsG, proteinG, fiberG, sugarG, micros
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fatG = try container.decodeIfPresent(Double.self, forKey: .fatG)
        saturatedFatG = try container.decodeIfPresent(Double.self, forKey: .saturatedFatG)
        transFatG = try container.decodeIfPresent(Double.self, forKey: .transFatG)
        cholesterolMg = try container.decodeIfPresent(Double.self, forKey: .cholesterolMg)
        carbsG = try container.decodeIfPresent(Double.self, forKey: .carbsG)
        proteinG = try container.decodeIfPresent(Double.self, forKey: .proteinG)
        fiberG = try container.decodeIfPresent(Double.self, forKey: .fiberG)
        sugarG = try container.decodeIfPresent(Double.self, forKey: .sugarG)
        micros = try container.decodeIfPresent([String: Double].self, forKey: .micros) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fatG, forKey: .fatG)
        try container.encodeIfPresent(saturatedFatG, forKey: .saturatedFatG)
        try container.encodeIfPresent(transFatG, forKey: .transFatG)
        try container.encodeIfPresent(cholesterolMg, forKey: .cholesterolMg)
        try container.encodeIfPresent(carbsG, forKey: .carbsG)
        try container.encodeIfPresent(proteinG, forKey: .proteinG)
        try container.encodeIfPresent(fiberG, forKey: .fiberG)
        try container.encodeIfPresent(sugarG, forKey: .sugarG)
        if !micros.isEmpty {
            try container.encode(micros, forKey: .micros)
        }
    }
}
