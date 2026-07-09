import Foundation

/// The JSON export/import format for everything the app itself stores:
/// the food/meal library, the weight goal, and water settings. Daily logs
/// live in Apple Health (exportable from the Health app) and are not here.
/// Meals reference foods by name — human-readable and survives re-import.
public struct LibraryExport: Codable, Sendable, Equatable {
    public struct FoodItem: Codable, Sendable, Equatable {
        public var name: String
        public var kcal: Double
        public var sodiumMg: Double
        public var servingDescription: String
        public var barcode: String?
        public var nutrients: NutrientValues?
        public var isFavorite: Bool?
        public var category: String?

        public init(
            name: String,
            kcal: Double,
            sodiumMg: Double,
            servingDescription: String,
            barcode: String?,
            nutrients: NutrientValues? = nil,
            isFavorite: Bool? = nil,
            category: String? = nil
        ) {
            self.name = name
            self.kcal = kcal
            self.sodiumMg = sodiumMg
            self.servingDescription = servingDescription
            self.barcode = barcode
            self.nutrients = nutrients
            self.isFavorite = isFavorite
            self.category = category
        }
    }

    public struct MealItemRef: Codable, Sendable, Equatable {
        public var foodName: String
        public var quantity: Double

        public init(foodName: String, quantity: Double) {
            self.foodName = foodName
            self.quantity = quantity
        }
    }

    public struct MealDef: Codable, Sendable, Equatable {
        public var name: String
        public var items: [MealItemRef]
        public var isFavorite: Bool?
        public var category: String?

        public init(name: String, items: [MealItemRef], isFavorite: Bool? = nil, category: String? = nil) {
            self.name = name
            self.items = items
            self.isFavorite = isFavorite
            self.category = category
        }
    }

    public struct GoalDef: Codable, Sendable, Equatable {
        public var targetWeightLb: Double
        public var targetDate: Date
        public var fallbackCurrentWeightLb: Double?

        public init(targetWeightLb: Double, targetDate: Date, fallbackCurrentWeightLb: Double?) {
            self.targetWeightLb = targetWeightLb
            self.targetDate = targetDate
            self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
        }
    }

    public struct WaterDef: Codable, Sendable, Equatable {
        public var servingOz: Double
        public var goalOz: Double

        public init(servingOz: Double, goalOz: Double) {
            self.servingOz = servingOz
            self.goalOz = goalOz
        }
    }

    public var version: Int
    public var exportedAt: Date
    public var foods: [FoodItem]
    public var meals: [MealDef]
    public var goal: GoalDef?
    public var water: WaterDef

    public init(
        version: Int = 1,
        exportedAt: Date,
        foods: [FoodItem],
        meals: [MealDef],
        goal: GoalDef?,
        water: WaterDef
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.foods = foods
        self.meals = meals
        self.goal = goal
        self.water = water
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryExport.self, from: data)
    }
}
