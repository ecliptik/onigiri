import Foundation

/// Day-keyed high-water mark for today's actual burn AS A BUDGET INPUT.
/// Health revises today's burn DOWNWARD when the watch syncs and its
/// samples reconcile with the phone's overlapping estimates — and the
/// 2.1.4 "budget follows actual burn" floor followed it down, moving
/// "kcal left" AGAINST the user with nothing eaten (from under budget to
/// over it across 45 idle minutes, 2026-07-22; the ratchet is the user's
/// pick).
/// The floor a budget derives from only rises within a calendar day.
/// Displayed burn totals (Active/Resting/Net) stay the honest Health
/// numbers — this marks ONLY the derivation input. App-group stored, so
/// the app and its widgets derive one budget; the watch keeps its own
/// mark over its own Health store — which is also why a mark set from a
/// bad read surfaces as the two devices DISAGREEING rather than as one
/// obviously wrong number.
public enum TodayBurnFloor {
    static let dayKey = "todayBurnFloorDay"
    static let kcalKey = "todayBurnFloorKcal"

    /// Today's burn, floored by the highest value seen today; a rise
    /// records the new mark. A mark from any previous day is ignored
    /// and replaced — the ratchet resets with the calendar day.
    ///
    /// `readAt` is WHEN the burn figure was read, and it exists because
    /// a read that STRADDLES MIDNIGHT describes neither day. Measured on
    /// device 2026-09-20: a plan load whose `todaySummary()` started
    /// before midnight returned the 19th's finished totals, the awaits
    /// landed at 00:01, and the mark went in under the 20th's key — so for
    /// the whole of the 20th the phone floored its budget at the previous
    /// day's full burn while the watch, which had no read in that window,
    /// used the day's real one. Several hundred kcal apart, one screen
    /// saying "left" and the other "over", and the ratchet only rises, so
    /// it could not converge before midnight.
    ///
    /// Passing nil keeps the pre-guard behavior, for a caller with no
    /// read timestamp to offer.
    public static func ratcheted(
        _ kcal: Double,
        readAt: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        let today = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        // Straddled: touch the store at all and the wrong day is locked
        // in until midnight. The value passes through unchanged so the
        // caller still renders something, and the next refresh — begun
        // and finished inside one day — sets the real mark seconds
        // later. Persisting is the only irreversible half.
        if let readAt,
           DeficitTargetHistory.dayKey(for: readAt, calendar: calendar) != today {
            return kcal
        }
        let defaults = SharedStore.defaults
        let mark = todayMark(now: now, calendar: calendar)
        guard kcal > mark else { return mark }
        defaults.set(today, forKey: dayKey)
        defaults.set(kcal, forKey: kcalKey)
        return kcal
    }

    /// Today's stored mark, or 0 — the READ half, with no write.
    ///
    /// A diagnostic must not move the thing it is measuring, and
    /// `DailyPlanLoader.diagnose` was calling `ratcheted` for its
    /// `floored=` field: printing the budget's inputs could RECORD a
    /// mark, and on a launch that straddled midnight it could do so by
    /// the very route every other call site is now guarded against
    /// (2026-09-20, found while explaining why the guard had not fixed
    /// the day already in progress).
    public static func todayMark(now: Date = .now, calendar: Calendar = .current) -> Double {
        let today = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        let defaults = SharedStore.defaults
        return defaults.string(forKey: dayKey) == today
            ? defaults.double(forKey: kcalKey) : 0
    }

    #if DEBUG
    /// Drop today's mark so the next read sets it afresh.
    ///
    /// The `readAt` guard stops a bad mark being WRITTEN; it cannot undo
    /// one already stored, and the ratchet only rises, so a poisoned day
    /// otherwise runs to midnight. Reached by launch argument
    /// (`--clear-burn-floor`) rather than any UI: outside a debugging
    /// session there is no such thing as a mark the user should be
    /// clearing by hand, and the state this recovers from can no longer
    /// be produced.
    public static func clearToday() {
        SharedStore.defaults.removeObject(forKey: dayKey)
        SharedStore.defaults.removeObject(forKey: kcalKey)
    }

    /// `--clear-burn-floor` on the process, honoured once per launch by
    /// both apps BEFORE their first plan load — after it, the stale mark
    /// has already been read back into the rendered budget.
    public static func clearTodayIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard arguments.contains("--clear-burn-floor") else { return false }
        clearToday()
        return true
    }
    #endif
}
