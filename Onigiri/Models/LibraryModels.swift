import Foundation
import SwiftData

@Model
final class Food {
    var name: String
    var kcal: Double
    var sodiumMg: Double
    var servingDescription: String
    var barcode: String?
    var createdAt: Date

    init(name: String, kcal: Double, sodiumMg: Double, servingDescription: String = "", barcode: String? = nil) {
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.servingDescription = servingDescription
        self.barcode = barcode
        self.createdAt = .now
    }
}

@Model
final class MealItem {
    var food: Food?
    var quantity: Double

    init(food: Food, quantity: Double = 1) {
        self.food = food
        self.quantity = quantity
    }

    var kcal: Double { (food?.kcal ?? 0) * quantity }
    var sodiumMg: Double { (food?.sodiumMg ?? 0) * quantity }
}

@Model
final class Meal {
    var name: String
    @Relationship(deleteRule: .cascade) var items: [MealItem]
    var createdAt: Date

    init(name: String, items: [MealItem]) {
        self.name = name
        self.items = items
        self.createdAt = .now
    }

    var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    var totalSodiumMg: Double { items.reduce(0) { $0 + $1.sodiumMg } }
}

@Model
final class GoalSettings {
    var targetWeightLb: Double
    var targetDate: Date
    /// Manual fallback when Apple Health has no weight samples yet.
    var fallbackCurrentWeightLb: Double?

    init(
        targetWeightLb: Double,
        targetDate: Date,
        fallbackCurrentWeightLb: Double? = nil
    ) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
    }
}
