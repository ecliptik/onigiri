import Foundation

/// Per-day snapshots of the deficit target, so history is judged by the
/// goal that was in force THAT day. The target recomputes from current
/// weight, target date, and trailing burn — without snapshots, losing
/// weight (or editing the goal) silently rewrote which past days earned
/// a badge, and streaks shrank overnight with no entry changing.
///
/// The last value recorded on a day stands: with no background runtime,
/// "the target when the day closed" is approximated by the target at the
/// app's last use that day. Days with no snapshot (pre-feature history,
/// days the app never ran) fall back to the current target, which is the
/// pre-snapshot behavior.
public enum DeficitTargetHistory {
    static let key = "deficitTargetByDay"
    /// ~13 months — covers every browsable surface, bounds growth.
    private static let keptDays = 400

    /// Stamp today's target; 0 records the "no goal — any deficit earns
    /// the badge" rule, distinct from having no snapshot at all.
    public static func recordToday(
        targetKcal: Double?, now: Date = .now, calendar: Calendar = .current
    ) {
        var stored = storedTargets()
        let todayKey = dayKey(for: now, calendar: calendar)
        let value = targetKcal ?? 0
        // Every plan load lands here (app, watch, every widget provider) —
        // skip the ~400-entry plist rewrite when nothing changed.
        guard stored[todayKey] != value else { return }
        stored[todayKey] = value
        if stored.count > keptDays {
            for stale in stored.keys.sorted().dropLast(keptDays) {
                stored.removeValue(forKey: stale)
            }
        }
        SharedStore.defaults.set(stored, forKey: key)
    }

    /// Snapshot targets keyed by start-of-day, for StreakCalendar.
    public static func targetsByDay(calendar: Calendar = .current) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: storedTargets().compactMap { key, value in
            date(fromDayKey: key, calendar: calendar).map { ($0, value) }
        })
    }

    /// The target recorded on `day`, or nil when that day has no snapshot.
    public static func target(on day: Date, calendar: Calendar = .current) -> Double? {
        storedTargets()[dayKey(for: day, calendar: calendar)]
    }

    private static func storedTargets() -> [String: Double] {
        (SharedStore.defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    /// "2026-07-12" — sorts chronologically as a string, locale-free.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
