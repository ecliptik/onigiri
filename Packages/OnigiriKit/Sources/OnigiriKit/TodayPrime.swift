import Foundation

/// The Today screen's FIRST FRAME on a cold launch: the last numbers
/// Health confirmed for today, written after each trustworthy refresh
/// and read back before the next launch's first Health query.
///
/// Display-only, and that is the whole contract. HealthKit stays the
/// store (CLAUDE.md, "Logging: HealthKit is the store"): nothing is ever
/// written INTO this by a log, nothing reads it to reach a verdict, and
/// the next `TodayModel.refresh()` replaces every field. It exists
/// because the model used to start at literal zeros and paint them —
/// "0 kcal balance", "Nothing logged yet.", the add-a-weigh-in hint —
/// for the half second HealthKit takes to wake on a cold launch, then
/// jump to the day's real figures (the user, 2026-09-16;
/// `plans/PLAN-today-first-paint.md`). Stale-but-true beats confidently
/// wrong: the widget's `widget.lastGoodSnapshot` and the watch's
/// `WatchStateCache` were built on the same sentence.
public struct TodayPrime: Codable, Sendable, Equatable {
    /// Bump whenever a field's MEANING changes. A mismatch is simply
    /// "no prime" — additions decode leniently on their own, but a
    /// semantic change must not be served as last night's truth.
    public static let currentSchema = 1

    public var schema: Int
    /// The calendar day the numbers describe (its start).
    public var day: Date
    public var summary: DailyEnergySummary
    public var dayBurnKcal: Double
    public var estimatedRestingKcal: Double?
    public var currentWeightLb: Double?
    public var averageBurnKcal: Double?
    public var weeklyTrendLb: Double?
    public var weightHistory: [WeightTrend.Point]
    public var trackedTotals: [Double]
    public var foodLog: [FoodLogEntry]
    public var waterLog: [WaterLogEntry]

    public init(
        schema: Int = TodayPrime.currentSchema,
        day: Date,
        summary: DailyEnergySummary,
        dayBurnKcal: Double,
        estimatedRestingKcal: Double?,
        currentWeightLb: Double?,
        averageBurnKcal: Double?,
        weeklyTrendLb: Double?,
        weightHistory: [WeightTrend.Point],
        trackedTotals: [Double],
        foodLog: [FoodLogEntry],
        waterLog: [WaterLogEntry]
    ) {
        self.schema = schema
        self.day = day
        self.summary = summary
        self.dayBurnKcal = dayBurnKcal
        self.estimatedRestingKcal = estimatedRestingKcal
        self.currentWeightLb = currentWeightLb
        self.averageBurnKcal = averageBurnKcal
        self.weeklyTrendLb = weeklyTrendLb
        self.weightHistory = weightHistory
        self.trackedTotals = trackedTotals
        self.foodLog = foodLog
        self.waterLog = waterLog
    }

    /// Same calendar day and same schema. Anything else is a stale day
    /// or an older app's shape, and either primes nothing — a new
    /// morning must open on placeholders, never on yesterday's log.
    public func isValid(now: Date = .now, calendar: Calendar = .current) -> Bool {
        schema == Self.currentSchema && calendar.isDate(day, inSameDayAs: now)
    }

    /// An all-zero day with nothing logged is what a SEALED store
    /// returns (locked device), not a fact about the day. Never cache
    /// it: served as "last good" on the next launch it is exactly the
    /// confident zero this exists to prevent — the widget's own lesson
    /// (`SnapshotLoader`, "writing that as last good poisons the
    /// fallback"). Resting burn is positive within a minute of
    /// midnight, so a genuine empty morning still qualifies.
    public var isTrustworthy: Bool {
        summary.intakeKcal > 0 || summary.activeBurnKcal > 0
            || summary.restingBurnKcal > 0 || !foodLog.isEmpty || !waterLog.isEmpty
    }
}
