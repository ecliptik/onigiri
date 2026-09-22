import Foundation

/// The Calendar's FIRST FRAME on a cold launch — `TodayPrime` and
/// `GoalPrime`'s sibling, under the same contract: display-only, written
/// only from a Health answer, replaced whole by the next
/// `CalendarModel.refresh()`.
///
/// It exists because the month used to open with no badges, "🍙 0" and a
/// "0 days" streak — printed as facts — for the length of the first
/// Health read, then fill in at once (the user, 2026-09-17: "do we need
/// to do the same for… Calendar"; yes — Foods reads SwiftData and is
/// complete on its first frame, the Calendar reads Health and is not).
///
/// Only the RAW reads are kept. Badges, the streak and the tracked-day
/// set are VERDICTS, and a verdict is never cached: they are re-derived
/// on apply by `recomputeBadges()`, the code a live refresh runs, against
/// today's date, the per-day rule history and the untracked threshold as
/// they stand NOW. A prime saved yesterday therefore cannot claim a
/// streak that ended overnight.
public struct CalendarPrime: Codable, Sendable, Equatable {
    /// Bump whenever a field's MEANING changes. A mismatch is "no prime".
    public static let currentSchema = 1

    /// A week, by `GoalPrime`'s reasoning: a trailing window of day
    /// totals from Tuesday is, on Thursday, the same month short two
    /// squares — for half a second.
    public static let maxAge: TimeInterval = 7 * 86_400

    public var schema: Int
    public var savedAt: Date
    /// The trailing window `refresh()` fetched — not the on-demand months
    /// a session browsed back to.
    public var totals: [DayEnergyTotals]
    public var targetDeficitKcal: Double?
    public var isMaintenance: Bool
    public var weightHistory: [WeightTrend.Point]
    /// The day card's tracked-metric slots for the day the tab opens on.
    /// Optional, so a v2.28.1 file (which has none) still decodes — an
    /// addition, not a change of meaning, hence no schema bump.
    public var dayCard: DayCard?

    /// The one part of this prime that belongs to a CALENDAR DAY. The
    /// month lasts a week; this lasts until midnight (`TodayPrime`'s
    /// rule), because the tab opens on today and yesterday's sodium under
    /// today's heading is a wrong number, not a stale one. Sodium and
    /// water ride `summary`; the other tracked nutrients are read per
    /// SLOT, and a slot total means nothing once the slot's setting has
    /// changed — `slotKeys` records what each was read as.
    public struct DayCard: Codable, Sendable, Equatable {
        public var day: Date
        public var summary: DailyEnergySummary
        public var slotKeys: [String]
        public var slotTotals: [Double?]

        public init(day: Date, summary: DailyEnergySummary,
                    slotKeys: [String], slotTotals: [Double?]) {
            self.day = day
            self.summary = summary
            self.slotKeys = slotKeys
            self.slotTotals = slotTotals
        }

        public func isValid(now: Date = .now, calendar: Calendar = .current) -> Bool {
            calendar.isDate(day, inSameDayAs: now)
        }

        /// An all-zero summary is what a sealed store returns, never a
        /// fact about a day (`TodayPrime.isTrustworthy`): resting burn
        /// is positive within a minute of midnight.
        public var isTrustworthy: Bool {
            summary.intakeKcal > 0 || summary.activeBurnKcal > 0 || summary.restingBurnKcal > 0
        }

        /// The slot totals, if they were read under `keys`; else none.
        public func slotTotals(ifReadAs keys: [String]) -> [Double?]? {
            slotKeys == keys ? slotTotals : nil
        }
    }

    public init(
        schema: Int = CalendarPrime.currentSchema,
        savedAt: Date,
        totals: [DayEnergyTotals],
        targetDeficitKcal: Double?,
        isMaintenance: Bool,
        weightHistory: [WeightTrend.Point],
        dayCard: DayCard? = nil
    ) {
        self.schema = schema
        self.savedAt = savedAt
        self.totals = totals
        self.targetDeficitKcal = targetDeficitKcal
        self.isMaintenance = isMaintenance
        self.weightHistory = weightHistory
        self.dayCard = dayCard
    }

    /// Same schema, written in the past, within `maxAge`. A prime from
    /// the FUTURE means the clock moved; its age cannot be known.
    public func isValid(now: Date = .now) -> Bool {
        schema == Self.currentSchema
            && savedAt <= now
            && now.timeIntervalSince(savedAt) <= Self.maxAge
    }

    /// A window with no energy in it at all is what a SEALED store
    /// returns (locked device) — never cache it, or the next launch opens
    /// on the empty month this exists to prevent (`TodayPrime`'s rule).
    /// Resting burn alone makes any real day positive.
    public var isTrustworthy: Bool {
        totals.contains { $0.intakeKcal > 0 || $0.burnKcal > 0 }
    }
}
