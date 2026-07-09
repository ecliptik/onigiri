import Foundation

/// One logged eating event, as read back from HealthKit.
/// `id` is the HealthKit correlation UUID, usable for deletion.
public struct FoodLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let kcal: Double
    public let sodiumMg: Double
    public let date: Date

    public init(id: UUID, name: String, kcal: Double, sodiumMg: Double, date: Date) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.date = date
    }
}
