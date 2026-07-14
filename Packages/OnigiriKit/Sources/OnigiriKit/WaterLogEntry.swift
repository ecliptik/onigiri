import Foundation

/// One logged water serving, as read back from HealthKit.
public struct WaterLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let oz: Double
    public let date: Date
    /// False for samples another app saved — see FoodLogEntry.editable.
    public let editable: Bool

    public init(id: UUID, oz: Double, date: Date, editable: Bool = true) {
        self.id = id
        self.oz = oz
        self.date = date
        self.editable = editable
    }
}
