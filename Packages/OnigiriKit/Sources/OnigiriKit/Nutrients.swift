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

/// A nutrient (or water) that can occupy one of Today's tracked-metric
/// slots. Day totals come from Health, so only nutrients with a dietary
/// type qualify — which excludes trans fat (app-only). Keys are stable
/// storage strings; micro cases reuse the Micronutrient raw values.
public enum TrackedNutrient: Hashable, Sendable, Identifiable {
    case water, sodium
    case fat, saturatedFat, polyunsaturatedFat, monounsaturatedFat
    case cholesterol, carbs, protein, fiber, sugar, caffeine
    case micro(Micronutrient)

    public var id: String { key }

    /// Picker groups, in display order — macros in nutrition-label
    /// order, matching the food form and the day detail.
    public static let general: [TrackedNutrient] = [.water, .sodium]
    public static let macros: [TrackedNutrient] = [
        .fat, .saturatedFat, .polyunsaturatedFat, .monounsaturatedFat,
        .cholesterol, .carbs, .fiber, .sugar, .protein, .caffeine,
    ]
    public static var all: [TrackedNutrient] {
        general + macros + Micronutrient.allCases.map(Self.micro)
    }

    public var key: String {
        switch self {
        case .water: "water"
        case .sodium: "sodium"
        case .fat: "fat"
        case .saturatedFat: "saturatedFat"
        case .polyunsaturatedFat: "polyunsaturatedFat"
        case .monounsaturatedFat: "monounsaturatedFat"
        case .cholesterol: "cholesterol"
        case .carbs: "carbs"
        case .protein: "protein"
        case .fiber: "fiber"
        case .sugar: "sugar"
        case .caffeine: "caffeine"
        case .micro(let micro): micro.rawValue
        }
    }

    public init?(key: String) {
        if let match = (Self.general + Self.macros).first(where: { $0.key == key }) {
            self = match
        } else if let micro = Micronutrient(rawValue: key) {
            self = .micro(micro)
        } else {
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .water: "Water"
        case .sodium: "Sodium"
        case .fat: "Fat"
        case .saturatedFat: "Saturated fat"
        case .polyunsaturatedFat: "Polyunsaturated fat"
        case .monounsaturatedFat: "Monounsaturated fat"
        case .cholesterol: "Cholesterol"
        case .carbs: "Carbohydrates"
        case .protein: "Protein"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .caffeine: "Caffeine"
        case .micro(let micro): micro.displayName
        }
    }

    /// The nutrient's label/Health unit, used for the target and the
    /// Today readout.
    public var unitSymbol: String {
        switch self {
        case .water: "oz"
        case .sodium, .cholesterol, .caffeine: "mg"
        case .fat, .saturatedFat, .polyunsaturatedFat, .monounsaturatedFat,
             .carbs, .protein, .fiber, .sugar: "g"
        case .micro(let micro): micro.unit.symbol
        }
    }

    /// The metric's default icon; a custom emoji per slot can override
    /// it. Water's actual icon is the app-wide water icon (SF droplet by
    /// default) — this emoji is only its fallback representation.
    public var defaultEmoji: String {
        switch self {
        case .water: "💧"
        case .sodium: "🧂"
        case .protein: "🥩"
        case .carbs: "🍞"
        case .fiber: "🌾"
        case .sugar: "🍬"
        case .fat: "🧈"
        case .saturatedFat: "🥓"
        case .polyunsaturatedFat: "🐟"
        case .monounsaturatedFat: "🫒"
        case .cholesterol: "🥚"
        case .caffeine: "☕"
        case .micro(let micro):
            Micronutrient.minerals.contains(micro) ? "🪨" : "💊"
        }
    }

    /// Inline label for Today's metric row and the Show toggles: sodium
    /// and water keep their long-standing lowercase copy; other nutrients
    /// read as named ("Fiber", "Vitamin B12").
    public var inlineName: String {
        switch self {
        case .sodium: "sodium"
        case .water: "water"
        default: displayName
        }
    }

    /// Per-item amount for library/log rows and meal totals, in this
    /// metric's unit — nil for water, which is a log, not a food fact.
    /// Missing nutrients read as 0, matching sodium's long-standing
    /// "0 mg Na" for foods that never carried it.
    public func itemAmount(sodiumMg: Double, nutrients: NutrientValues) -> Double? {
        switch self {
        case .water: nil
        case .sodium: sodiumMg
        case .fat: nutrients.fatG ?? 0
        case .saturatedFat: nutrients.saturatedFatG ?? 0
        case .polyunsaturatedFat: nutrients.polyunsaturatedFatG ?? 0
        case .monounsaturatedFat: nutrients.monounsaturatedFatG ?? 0
        case .cholesterol: nutrients.cholesterolMg ?? 0
        case .carbs: nutrients.carbsG ?? 0
        case .protein: nutrients.proteinG ?? 0
        case .fiber: nutrients.fiberG ?? 0
        case .sugar: nutrients.sugarG ?? 0
        case .caffeine: nutrients.caffeineMg ?? 0
        case .micro(let micro): nutrients[micro] ?? 0
        }
    }

    /// The row-caption unit: sodium keeps its long-standing "mg Na"
    /// shorthand; everything else names itself ("g Protein",
    /// "µg Vitamin B12").
    public var captionUnit: String {
        switch self {
        case .sodium: "mg Na"
        default: "\(unitSymbol) \(displayName)"
        }
    }

    /// The first tracked-metric slot that applies to FOOD items — water
    /// is log-only and a cleared slot doesn't parse, so both skip to the
    /// next; sodium when nothing qualifies (the long-standing default).
    public static func firstFoodMetric(slot1: String, slot2: String) -> TrackedNutrient {
        for key in [slot1, slot2] {
            if let metric = TrackedNutrient(key: key), metric != .water { return metric }
        }
        return .sodium
    }

    /// Whether picking this nutrient starts as a ceiling (limit) or a
    /// floor (goal); the user can flip it.
    public var defaultMode: TrackedMetricMode {
        switch self {
        case .sodium, .sugar, .fat, .saturatedFat, .cholesterol, .caffeine:
            .limit
        default:
            .goal
        }
    }

    /// Seed target when first picked — FDA adult daily values (water is
    /// the app's long-standing 64 oz). A starting point, not advice; the
    /// user sets their own number in Settings.
    public var defaultTarget: Double {
        switch self {
        case .water: 64
        case .sodium: 2300
        case .fat: 78
        case .saturatedFat: 20
        case .polyunsaturatedFat: 22
        case .monounsaturatedFat: 44
        case .cholesterol: 300
        case .carbs: 275
        case .protein: 50
        case .fiber: 28
        case .sugar: 50
        case .caffeine: 400
        case .micro(let micro):
            switch micro {
            case .potassium: 4700
            case .calcium: 1300
            case .iron: 18
            case .magnesium: 420
            case .zinc: 11
            case .phosphorus: 1250
            case .selenium: 55
            case .copper: 0.9
            case .manganese: 2.3
            case .iodine: 150
            case .chromium: 35
            case .molybdenum: 45
            case .chloride: 2300
            case .vitaminA: 900
            case .vitaminC: 90
            case .vitaminD: 20
            case .vitaminE: 15
            case .vitaminB6: 1.7
            case .vitaminB12: 2.4
            case .folate: 400
            case .vitaminK: 120
            case .thiamin: 1.2
            case .riboflavin: 1.3
            case .niacin: 16
            case .pantothenicAcid: 5
            case .biotin: 30
            }
        }
    }
}

/// Whether a tracked metric's target is a ceiling or a floor.
public enum TrackedMetricMode: String, Sendable {
    case limit, goal
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
    /// Stored, not computed: every +/scaled/isEmpty/encode/decode hit
    /// rebuilt this array (amplified by sync pushes iterating the whole
    /// library). Key paths aren't formally Sendable, but these are
    /// immutable instances — the codebase's documented
    /// nonisolated(unsafe) case (Logger, UserDefaults).
    private nonisolated(unsafe) static let scalarFields: [(WritableKeyPath<NutrientValues, Double?>, CodingKeys)] = [
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
    ]

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
