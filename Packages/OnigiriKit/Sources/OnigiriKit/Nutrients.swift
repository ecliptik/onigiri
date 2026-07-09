import Foundation

/// Meal-slot categories for organizing the food library.
public enum FoodCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    public var id: String { rawValue }
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
