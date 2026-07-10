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

/// Optional extended nutrients (grams). Calories and sodium remain the
/// first-class fields; these ride along when known.
public struct NutrientValues: Sendable, Equatable, Codable {
    public var fatG: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fiberG: Double?
    public var sugarG: Double?

    public init(
        fatG: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil
    ) {
        self.fatG = fatG
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fiberG = fiberG
        self.sugarG = sugarG
    }

    public var isEmpty: Bool {
        fatG == nil && carbsG == nil && proteinG == nil && fiberG == nil && sugarG == nil
    }

    public func scaled(by factor: Double) -> NutrientValues {
        NutrientValues(
            fatG: fatG.map { $0 * factor },
            carbsG: carbsG.map { $0 * factor },
            proteinG: proteinG.map { $0 * factor },
            fiberG: fiberG.map { $0 * factor },
            sugarG: sugarG.map { $0 * factor }
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
            carbsG: add(lhs.carbsG, rhs.carbsG),
            proteinG: add(lhs.proteinG, rhs.proteinG),
            fiberG: add(lhs.fiberG, rhs.fiberG),
            sugarG: add(lhs.sugarG, rhs.sugarG)
        )
    }
}
