import Foundation

/// Today's totals as read from HealthKit.
public struct DailyEnergySummary: Sendable, Equatable, Codable {
    public var intakeKcal: Double
    public var activeBurnKcal: Double
    public var restingBurnKcal: Double
    public var sodiumMg: Double
    public var waterOz: Double

    public init(
        intakeKcal: Double,
        activeBurnKcal: Double,
        restingBurnKcal: Double,
        sodiumMg: Double,
        waterOz: Double
    ) {
        self.intakeKcal = intakeKcal
        self.activeBurnKcal = activeBurnKcal
        self.restingBurnKcal = restingBurnKcal
        self.sodiumMg = sodiumMg
        self.waterOz = waterOz
    }

    public static let zero = DailyEnergySummary(
        intakeKcal: 0, activeBurnKcal: 0, restingBurnKcal: 0, sodiumMg: 0, waterOz: 0
    )

    public var totalBurnKcal: Double { activeBurnKcal + restingBurnKcal }

    /// The home-screen meter: intake − (active + resting). Negative is a deficit.
    public var balanceKcal: Double { intakeKcal - totalBurnKcal }
}
