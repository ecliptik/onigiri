import Foundation

/// Whether a Health read came back empty because the store was SEALED,
/// rather than because there was genuinely nothing to read.
///
/// This replaces `isStoreLocked()`, which asked the question in a way that
/// cannot be answered. That probe ran one sample query and reported
/// "locked" only if it threw `errorDatabaseInaccessible` — but Apple does
/// not promise a throw. The contract is the opposite: *"reads do not
/// reliably work when the device is locked"* and *"for reads, run a query
/// and accept that empty results are valid."* A sealed store is allowed to
/// answer EMPTY, and through that API an empty result is indistinguishable
/// from "no samples". So no probe of any type can tell the two apart, and
/// swapping in a different type would not have helped.
///
/// The question therefore has to change: instead of interrogating the
/// store about its mood, validate the RESULT against something a good read
/// must produce. Weight is that something — it is read on every plan load,
/// it is write-through cached with a day stamp, and it does not vanish
/// between one render and the next. A nil weight standing beside a weight
/// cached today or yesterday is a bad read. The same nil with nothing
/// cached recently is a user who has no weigh-ins, and must be believed.
///
/// Confirmed on device, from the phone's own plan journal (2026-08-08):
///
///     plan 08-08 08:39 act=51 restM=677 restE=1824 wt=212   ← good
///     plan 08-08 08:39 act=0  restM=0   restE=NIL  wt=NIL   ← sealed
///     plan 08-08 09:35 act=0  restM=0   restE=NIL  wt=NIL   ← sealed
///     plan 08-08 12:10 act=0  restM=0   restE=NIL  wt=NIL   ← sealed
///
/// Three in one day, one of them in the same MINUTE as a healthy read —
/// and `isStoreLocked()` called every one of them "open", which is how a
/// false zero reached the burn gate's baseline. Note `wt=NIL` is the
/// discriminator: `act=0` is legitimately true at 6 am, so burn can never
/// be the signal.
public enum HealthReadTrust {
    /// - Parameters:
    ///   - weightLb: what this read returned for body mass (nil if the
    ///     query threw OR came back empty — deliberately the same case).
    ///   - cachedDay: the day stamp on the last weight we successfully
    ///     read, from `HealthKitService.cachedPlanWeightLb()`.
    public static func looksSealed(
        weightLb: Double?,
        cachedDay: String?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Bool {
        // A weight in hand is proof enough that the store answered.
        guard weightLb == nil, let cachedDay else { return false }
        // Older than the freshness window: treat the absence as real, so
        // deleting every weigh-in doesn't freeze the widgets on a stale
        // snapshot forever. It self-heals in two days.
        return WatchSync.isRecentDay(cachedDay, calendar: calendar, now: now)
    }

    /// Whether a plan built from this read may be STAMPED into
    /// `DeficitTargetHistory`.
    ///
    /// The seal check was live on all three RENDER paths and absent from
    /// the one PERSISTENCE path, which is worse than the bug it was
    /// written for: a bad render is replaced by the next good one, a bad
    /// stamp is permanent. `DeficitTargetHistory` records "the last value
    /// recorded on a day stands", and `recordToday` writes `targetKcal ??
    /// 0` — which decodes to `DayBadgeRule.anyDeficit`, "no goal, any
    /// deficit earns the badge". So one sealed plan load late in the day
    /// silently re-graded that day to a laxer rule, forever. Confirmed on
    /// device 2026-08-18 from the phone's own plan journal: five `wt=NIL`
    /// reads across two days, interleaved with healthy ones.
    ///
    /// Deliberately NARROW. It refuses exactly one case — a weight goal
    /// whose target came back nil beside a weight the store had a moment
    /// ago — because every other nil is real information the history is
    /// supposed to keep:
    ///
    /// - No goal at all: 0 is the correct stamp, and no weight is even
    ///   read on that path.
    /// - Maintenance: the sentinel is read off the GOAL, not off Health,
    ///   so nothing the store withheld can change what gets written.
    /// - A user with genuinely no weigh-ins (nil weight, nothing cached
    ///   recently): `looksSealed` believes that absence, and so does this
    ///   — it is the existing behavior and it must survive.
    ///
    /// A stamped 0 keeps its meaning; nothing already stored is rewritten.
    public static func mayStampPlan(
        deficitTargetKcal: Double?,
        /// A live weight goal — not maintenance, not the goal-less path.
        hasWeightGoal: Bool,
        /// The weight the target was derived from (nil when the read
        /// came back empty).
        weightLb: Double?,
        cachedDay: String?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Bool {
        guard hasWeightGoal, deficitTargetKcal == nil else { return true }
        return !looksSealed(
            weightLb: weightLb, cachedDay: cachedDay, calendar: calendar, now: now
        )
    }
}
