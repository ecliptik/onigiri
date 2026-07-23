import Foundation

/// Day-keyed high-water mark for today's actual burn AS A BUDGET INPUT.
/// Health revises today's burn DOWNWARD when the watch syncs and its
/// samples reconcile with the phone's overlapping estimates — and the
/// 2.1.4 "budget follows actual burn" floor followed it down, moving
/// "kcal left" AGAINST the user with nothing eaten (160 under → 65 over
/// across 45 idle minutes, 2026-07-22; the ratchet is the user's pick).
/// The floor a budget derives from only rises within a calendar day.
/// Displayed burn totals (Active/Resting/Net) stay the honest Health
/// numbers — this marks ONLY the derivation input. App-group stored, so
/// the app and its widgets derive one budget; the watch keeps its own
/// mark over its own Health store.
public enum TodayBurnFloor {
    static let dayKey = "todayBurnFloorDay"
    static let kcalKey = "todayBurnFloorKcal"

    /// Today's burn, floored by the highest value seen today; a rise
    /// records the new mark. A mark from any previous day is ignored
    /// and replaced — the ratchet resets with the calendar day.
    public static func ratcheted(
        _ kcal: Double, now: Date = .now, calendar: Calendar = .current
    ) -> Double {
        let today = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        let defaults = SharedStore.defaults
        let mark = defaults.string(forKey: dayKey) == today
            ? defaults.double(forKey: kcalKey) : 0
        guard kcal > mark else { return mark }
        defaults.set(today, forKey: dayKey)
        defaults.set(kcal, forKey: kcalKey)
        return kcal
    }
}
