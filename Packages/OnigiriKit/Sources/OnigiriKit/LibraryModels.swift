import Foundation
import SwiftData

@Model
public final class Food {
    public var name: String
    public var kcal: Double
    public var sodiumMg: Double
    public var servingDescription: String
    public var barcode: String?
    public var createdAt: Date

    public init(name: String, kcal: Double, sodiumMg: Double, servingDescription: String = "", barcode: String? = nil) {
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.servingDescription = servingDescription
        self.barcode = barcode
        self.createdAt = .now
    }
}

@Model
public final class MealItem {
    public var food: Food?
    public var quantity: Double

    public init(food: Food, quantity: Double = 1) {
        self.food = food
        self.quantity = quantity
    }

    public var kcal: Double { (food?.kcal ?? 0) * quantity }
    public var sodiumMg: Double { (food?.sodiumMg ?? 0) * quantity }
}

@Model
public final class Meal {
    /// Stable external identifier, used by widget configuration entities.
    public var uuid: UUID
    public var name: String
    @Relationship(deleteRule: .cascade) public var items: [MealItem]
    public var createdAt: Date

    public init(name: String, items: [MealItem]) {
        self.uuid = UUID()
        self.name = name
        self.items = items
        self.createdAt = .now
    }

    public var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var totalSodiumMg: Double { items.reduce(0) { $0 + $1.sodiumMg } }
}

@Model
public final class GoalSettings {
    public var targetWeightLb: Double
    public var targetDate: Date
    /// Manual fallback when Apple Health has no weight samples yet.
    public var fallbackCurrentWeightLb: Double?

    public init(
        targetWeightLb: Double,
        targetDate: Date,
        fallbackCurrentWeightLb: Double? = nil
    ) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
    }
}

/// Storage shared between the app and its widget extension via the App Group.
public enum SharedStore {
    public static let appGroupID = "group.com.ecliptik.Onigiri"

    public static let waterServingKey = "waterServingOz"
    public static let waterGoalKey = "waterGoalOz"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static var waterServingOz: Double {
        let value = defaults.double(forKey: waterServingKey)
        return value > 0 ? value : 12
    }

    public static var waterGoalOz: Double {
        let value = defaults.double(forKey: waterGoalKey)
        return value > 0 ? value : 64
    }

    /// SwiftData container in the App Group so widgets can read the library.
    /// Falls back to the default location if the entitlement is missing.
    public static func modelContainer() throws -> ModelContainer {
        let schema = Schema([Food.self, Meal.self, GoalSettings.self])
        if let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let config = ModelConfiguration(url: base.appendingPathComponent("Onigiri.sqlite"))
            return try ModelContainer(for: schema, configurations: [config])
        }
        return try ModelContainer(for: schema, configurations: [ModelConfiguration()])
    }
}
