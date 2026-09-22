import Foundation

/// The Goal screen's FIRST FRAME on a cold launch: what Health last said
/// about weight and burn, written after each trustworthy load and read
/// back before the next launch's first Health query. `TodayPrime`'s
/// sibling, for the tab next door.
///
/// Display-only, and that is the whole contract. HealthKit stays the
/// store: nothing is written INTO this except from a Health answer,
/// nothing SAVES from it (`GoalView` keeps Save shut until Health has
/// answered this launch), and the next `GoalModel.loadIfStale()` replaces
/// every field. It exists because Goal used to open on a blank where the
/// chart goes and a grey bar where the weight goes, then fill all at once
/// when HealthKit woke — correct, and abrupt (the user, 2026-09-17, the
/// same day the placeholders went in). Only the RAW reads are kept; the
/// daily lows, the smoothed line and the basis weight are re-derived on
/// apply, by the same code a live load runs, so a prime cannot disagree
/// with the settings it is shown under.
public struct GoalPrime: Codable, Sendable, Equatable {
    /// Bump whenever a field's MEANING changes. A mismatch is simply
    /// "no prime".
    public static let currentSchema = 1

    /// A week. Unlike Today's log, none of this belongs to a calendar
    /// day — a 90-day weight history from Tuesday is still, on Thursday,
    /// nearly the chart Health is about to return, and "nearly, for half
    /// a second" is the point. Past a week it is a different chart, and
    /// the placeholders are the honest first frame.
    public static let maxAge: TimeInterval = 7 * 86_400

    public var schema: Int
    public var savedAt: Date
    public var healthWeightLb: Double?
    public var averageBurnKcal: Double?
    public var estimatedRestingKcal: Double?
    public var weightHistory: [WeightTrend.Point]
    public var dailyTotals: [DayEnergyTotals]

    public init(
        schema: Int = GoalPrime.currentSchema,
        savedAt: Date,
        healthWeightLb: Double?,
        averageBurnKcal: Double?,
        estimatedRestingKcal: Double?,
        weightHistory: [WeightTrend.Point],
        dailyTotals: [DayEnergyTotals]
    ) {
        self.schema = schema
        self.savedAt = savedAt
        self.healthWeightLb = healthWeightLb
        self.averageBurnKcal = averageBurnKcal
        self.estimatedRestingKcal = estimatedRestingKcal
        self.weightHistory = weightHistory
        self.dailyTotals = dailyTotals
    }

    /// Same schema, written in the past, and within `maxAge`. A prime
    /// stamped in the FUTURE means the clock moved; its age cannot be
    /// known, so it primes nothing.
    public func isValid(now: Date = .now) -> Bool {
        schema == Self.currentSchema
            && savedAt <= now
            && now.timeIntervalSince(savedAt) <= Self.maxAge
    }

    /// No weight and no history is what a SEALED store returns (locked
    /// device), not a fact about the scale. Never cache it: served as the
    /// next launch's first frame it is the false "No weight in Apple
    /// Health yet" the placeholders were built to stop (`TodayPrime`'s
    /// rule, and the widget's before it). Someone who truly has no
    /// weigh-ins has nothing worth priming either.
    public var isTrustworthy: Bool {
        healthWeightLb != nil || !weightHistory.isEmpty
    }
}
