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
    /// Stored value marking a maintenance day (the band rule). Values
    /// are otherwise deficit targets ≥ 0, so any negative is safe; the
    /// sentinel never leaves this file undecoded. Forward-only: days
    /// stamped 0 before the band rule existed keep their any-deficit
    /// judgment — no badge history rewrites.
    static let maintenanceSentinel = -1.0

    /// Stamp today's rule; 0 records "no goal — any deficit earns the
    /// badge" (distinct from having no snapshot at all), and
    /// maintenance days record the band-rule sentinel.
    public static func recordToday(
        targetKcal: Double?, isMaintenance: Bool = false,
        now: Date = .now, calendar: Calendar = .current
    ) {
        var stored = storedTargets()
        let todayKey = dayKey(for: now, calendar: calendar)
        let value = isMaintenance ? maintenanceSentinel : (targetKcal ?? 0)
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

    /// Snapshot rules keyed by start-of-day, for StreakCalendar — the
    /// sentinel decodes here, at the API boundary, never in callers.
    public static func rulesByDay(calendar: Calendar = .current) -> [Date: DayBadgeRule] {
        Dictionary(uniqueKeysWithValues: storedTargets().compactMap { key, value in
            date(fromDayKey: key, calendar: calendar).map { ($0, rule(fromStored: value)) }
        })
    }

    /// The deficit target recorded on `day` — nil when the day has no
    /// snapshot OR was a maintenance day (maintenance has no deficit
    /// target; use `hasSnapshot(on:)` to tell the two apart).
    public static func target(on day: Date, calendar: Calendar = .current) -> Double? {
        guard let value = storedTargets()[dayKey(for: day, calendar: calendar)],
              value >= 0
        else { return nil }
        return value
    }

    /// Whether any rule was stamped on `day` — the "did today's plan
    /// load run yet" check, which `target(on:)`'s nil can no longer
    /// answer (maintenance days read nil there by design).
    public static func hasSnapshot(on day: Date, calendar: Calendar = .current) -> Bool {
        storedTargets()[dayKey(for: day, calendar: calendar)] != nil
    }

    private static func rule(fromStored value: Double) -> DayBadgeRule {
        if value < 0 { return .maintenanceBand }
        return value > 0 ? .deficitTarget(value) : .anyDeficit
    }

    /// Drops every snapshot — Settings' goals reset. Past days fall back
    /// to judging by the current target, the pre-snapshot behavior.
    public static func reset() {
        SharedStore.defaults.removeObject(forKey: key)
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
