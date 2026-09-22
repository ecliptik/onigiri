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

    /// Intake − raw measured burn. Negative is a deficit.
    ///
    /// **Not a verdict.** Use `DayBudget.deficit(intakeKcal:dayBurnKcal:)`
    /// for anything a user reads as a judgment — banked, Net, the gauge,
    /// the balance headline, "did this day earn its badge". This one
    /// subtracts only the resting Health has RECORDED, while every
    /// budget in the app is cut from the whole day's resting credited up
    /// front, so the two disagree by the un-accrued balance: at 9am
    /// that's over a thousand kcal, and it read as the app contradicting
    /// itself on three separate screens (2026-08-02). It survives for
    /// the one honest use — reporting what Health measured.
    public var balanceKcal: Double { intakeKcal - totalBurnKcal }
}
