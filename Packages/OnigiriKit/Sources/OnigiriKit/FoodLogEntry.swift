import Foundation

/// One logged eating event, as read back from HealthKit.
/// `id` is the HealthKit correlation UUID, usable for deletion.
public struct FoodLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let kcal: Double
    public let sodiumMg: Double
    public let date: Date
    /// Meal slot the entry belongs to. Stored with the entry when logged
    /// from the app; inferred from the time of day for entries without one
    /// (older logs, watch logs, other apps).
    public let category: FoodCategory

    public init(
        id: UUID,
        name: String,
        kcal: Double,
        sodiumMg: Double,
        date: Date,
        category: FoodCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.date = date
        self.category = category ?? FoodCategory.slot(for: date)
    }
}
