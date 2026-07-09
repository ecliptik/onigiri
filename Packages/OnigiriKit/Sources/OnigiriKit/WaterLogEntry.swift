import Foundation

/// One logged water serving, as read back from HealthKit.
public struct WaterLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let oz: Double
    public let date: Date

    public init(id: UUID, oz: Double, date: Date) {
        self.id = id
        self.oz = oz
        self.date = date
    }
}
