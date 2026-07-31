import Foundation

/// Per-day snapshots of the burn the plan expected, the twin of
/// `DeficitTargetHistory`. Together they pin a day's budget: expected
/// burn minus that day's deficit target.
///
/// Both drift — the trailing average moves as you live, the target moves
/// as the scale and the calendar move — so without snapshots, today's
/// numbers silently re-judge every past day. That is the same failure the
/// target snapshots were added for; the budget needs it just as much now
/// that the budget IS the verdict.
public enum PlanBurnHistory {
    static let key = "planBurnByDay"
    /// ~13 months, matching DeficitTargetHistory.
    private static let keptDays = 400

    /// Stamp the burn today's plan is built on. Last value of the day
    /// stands — with no background runtime, "what the plan expected when
    /// the day closed" is approximated by the last time the app ran.
    public static func recordToday(
        expectedBurnKcal: Double?, now: Date = .now, calendar: Calendar = .current
    ) {
        guard let expectedBurnKcal, expectedBurnKcal > 0 else { return }
        var stored = storedBurns()
        let todayKey = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        // Every plan load lands here (app, watch, every widget provider) —
        // skip the plist rewrite when nothing moved.
        guard stored[todayKey] != expectedBurnKcal else { return }
        stored[todayKey] = expectedBurnKcal
        if stored.count > keptDays {
            for stale in stored.keys.sorted().dropLast(keptDays) {
                stored.removeValue(forKey: stale)
            }
        }
        SharedStore.defaults.set(stored, forKey: key)
    }

    /// The expected burn recorded on `day`, or nil for days that predate
    /// snapshots or that the app never ran.
    public static func expectedBurn(on day: Date, calendar: Calendar = .current) -> Double? {
        storedBurns()[DeficitTargetHistory.dayKey(for: day, calendar: calendar)]
    }

    /// Snapshots keyed by start-of-day, for judging a whole month at once.
    public static func burnsByDay(calendar: Calendar = .current) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: storedBurns().compactMap { key, value in
            DeficitTargetHistory.date(fromDayKey: key, calendar: calendar).map { ($0, value) }
        })
    }

    /// Settings' goals reset — past days fall back to the current
    /// expectation, the pre-snapshot behavior.
    public static func reset() {
        SharedStore.defaults.removeObject(forKey: key)
    }

    private static func storedBurns() -> [String: Double] {
        (SharedStore.defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }
}
