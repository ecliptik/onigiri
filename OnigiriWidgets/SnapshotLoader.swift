import Foundation
import OnigiriKit

/// Everything a widget needs to render one moment of the day.
/// Codable: the last good snapshot persists in the App Group so a
/// background reload against a LOCKED phone (sealed Health store —
/// e.g. a watch log syncing in overnight) re-renders it instead of
/// replacing a correct widget with confident zeros until unlock.
struct DaySnapshot: Codable {
    var summary: DailyEnergySummary
    var deficitTargetKcal: Double?
    var remainingKcal: Double?
    /// 0...1 fill of the onigiri gauge (banked deficit / daily target).
    var gaugeProgress: Double
    var waterGoalOz: Double
    /// Health access never granted — a confident green "0 kcal" before
    /// setup was indistinguishable from a genuinely balanced day.
    var needsSetup = false
    /// Maintenance mode's gauge counts DOWN from a full budget (share
    /// left to eat), the deficit gauge counts UP from zero — the
    /// midnight pre-render below must know which way is "fresh day".
    var isMaintenance = false
    /// Day totals for the two tracked-metric slots (Today card only).
    /// Optional so a pre-2.1 cached last-good snapshot still decodes;
    /// nil falls back to the summary's sodium/water, which is also the
    /// answer whenever the slots hold their defaults.
    var trackedTotals: [Double]?

    static let placeholder = DaySnapshot(
        summary: DailyEnergySummary(
            intakeKcal: 1280, activeBurnKcal: 385, restingBurnKcal: 1120,
            sodiumMg: 1780, waterOz: 36
        ),
        deficitTargetKcal: 583,
        remainingKcal: 437,
        gaugeProgress: 0.38,
        waterGoalOz: 64
    )

    /// The plan-state view of this snapshot, for the shared accessory
    /// views (budget reconstructed: remaining was budget − intake).
    var planState: DailyPlanLoader.State {
        let budget = remainingKcal.map { $0 + summary.intakeKcal }
        return DailyPlanLoader.State(
            summary: summary,
            deficitTargetKcal: deficitTargetKcal,
            gaugeProgress: gaugeProgress,
            dailyBudgetKcal: budget,
            // budget = dayBurn − deficit, so the burn comes back out
            // without widening the persisted snapshot (a pre-2.13
            // last-good blob still decodes, and reconstructs the same
            // way its budget was built).
            dayBurnKcal: budget.map { $0 + (deficitTargetKcal ?? 0) }
        )
    }

    /// The just-after-midnight render: nothing eaten or burned yet, the
    /// same plan. Pre-rendered into the timeline so yesterday's numbers
    /// never show into the new day while WidgetKit waits out its budget.
    var newDay: DaySnapshot {
        DaySnapshot(
            summary: .zero,
            deficitTargetKcal: deficitTargetKcal,
            // The full budget again: remaining was budget − intake.
            remainingKcal: remainingKcal.map { $0 + summary.intakeKcal },
            // Deficit gauges start the day empty (nothing banked);
            // the maintenance gauge starts FULL (whole budget left) —
            // zero here rendered an empty onigiri all morning.
            gaugeProgress: isMaintenance ? 1 : 0,
            waterGoalOz: waterGoalOz,
            needsSetup: needsSetup,
            isMaintenance: isMaintenance,
            trackedTotals: [0, 0]
        )
    }

    /// A slot's day total. Sodium/water ride the summary — no second
    /// query, and the numbers can't disagree with the rest of the card
    /// (TodayModel's rule); custom nutrients read the dedicated query's
    /// result, 0 when a pre-2.1 cached snapshot predates it.
    func trackedTotal(slot: Int) -> Double {
        switch SharedStore.trackedNutrient(slot: slot) {
        case .sodium?: return summary.sodiumMg
        case .water?: return summary.waterOz
        case nil: return 0
        default:
            guard let totals = trackedTotals, totals.indices.contains(slot - 1) else { return 0 }
            return totals[slot - 1]
        }
    }
}

/// Next midnight — the second entry EVERY timeline carries.
///
/// Load-bearing rule, learned the hard way (2026-07-26: the home-screen
/// widget still showed yesterday's kcal-left well into the morning, and
/// only corrected when the app was opened). Every provider used to
/// append the pre-rendered new-day entry only when midnight fell inside
/// the poll window — so a timeline built at 22:15 shipped ONE entry and
/// leaned on WidgetKit granting a reload before 00:00. Overnight, with
/// the phone idle, that reload is exactly what the budget defers, and a
/// single stale entry then renders until something forces a reload.
///
/// A future-dated entry needs no reload and no budget: WidgetKit
/// renders it on schedule from a timeline it already holds. Gating it
/// on the reload cadence defeated the one mechanism that survives the
/// budget. So: always append, and let the policy handle the cadence.
func nextMidnight(after now: Date) -> Date? {
    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
}

/// The poll every phone provider commits to, in one place so the four of
/// them can't drift (they already share the midnight rule above).
///
/// Three cadences, in priority order: a known-stale cached snapshot comes
/// back in minutes; recent activity — a log OR burn that moved enough to
/// matter — keeps the short window; otherwise the waking-hours cadence.
func nextRefresh(after now: Date, wasCached: Bool = false) -> (date: Date, interval: TimeInterval) {
    let interval = wasCached
        ? WidgetRefreshPolicy.sealedStoreRetry
        : WidgetRefreshPolicy.nextPoll(now: now, lastActivityAt: WidgetBurnGate.lastActivityAt())
    return (now.addingTimeInterval(interval), interval)
}

@MainActor
enum SnapshotLoader {
    /// A load and how much to trust its freshness. `wasCached` means the
    /// Health store was sealed and this is the last good snapshot, not a
    /// live read — the provider must then come back SOON rather than
    /// committing the full poll cadence to a value it already knows is
    /// stale. (Before this, a poll that landed while the phone sat locked
    /// in a pocket — i.e. most of any walk — served the old number and
    /// re-committed it for another full hour.)
    struct Load {
        var snapshot: DaySnapshot
        var wasCached = false
    }

    /// The widget process is memory-capped, so it must not open SwiftData.
    /// The phone mirrors the goal into the App Group on every sync push;
    /// the shared DailyPlanLoader does the rest, like the watch.
    static func load() async -> Load {
        // Sealed store (locked phone): serve the last good snapshot —
        // its values are stale-but-true; zeros are confidently wrong.
        if await HealthKitService().healthReadLooksSealed(),
           let data = SharedStore.defaults.data(forKey: lastGoodKey),
           let cached = try? JSONDecoder().decode(DaySnapshot.self, from: data) {
            return Load(snapshot: cached, wasCached: true)
        }
        let needsSetup = await PlanCache.needsSetup()
        let goal = WatchSync.loadGoal()
        let state = await PlanCache.state(goal: goal)
        let snapshot = DaySnapshot(
            summary: state.summary,
            deficitTargetKcal: state.deficitTargetKcal,
            remainingKcal: state.remainingKcal,
            gaugeProgress: state.gaugeProgress,
            waterGoalOz: SharedStore.waterGoalOz,
            needsSetup: needsSetup,
            isMaintenance: goal?.isMaintenance ?? false,
            trackedTotals: await trackedTotals()
        )
        // Same trustworthiness test as the baseline below, for the same
        // reason: a store that sealed AFTER the check above yields a zero
        // day, and writing that as "last good" poisons the fallback —
        // the next sealed render would then serve those zeros as
        // stale-but-true, which is exactly what the cache exists to stop.
        if !needsSetup, state.dailyBudgetKcal != nil,
           let data = try? JSONEncoder().encode(snapshot) {
            SharedStore.defaults.set(data, forKey: lastGoodKey)
        }
        // The burn gate's baseline: record what this render is about to
        // show, so the observer compares against the number on screen
        // rather than against whatever it last happened to read.
        //
        // NOT on a degenerate read. This second guard predates
        // `healthReadLooksSealed` and outlives it: the seal check runs
        // BEFORE the reads, so a device that locks in between still lands
        // here with `act=0 restM=0 restE=NIL wt=NIL` (observed 2026-08-07,
        // and three more times on 08-08). A false baseline is worse than
        // none — it made the next observer fire see a 106 kcal jump that
        // had not happened, and the mirror case would suppress a reload
        // that should have run. No plan (`dailyBudgetKcal == nil`) means
        // the read is not trustworthy enough to compare against.
        if !needsSetup, state.dailyBudgetKcal != nil {
            WidgetBurnGate.recordRendered(activeKcal: state.summary.activeBurnKcal)
        }
        return Load(snapshot: snapshot)
    }

    /// Day totals for the tracked slots the summary doesn't already
    /// carry: only a slot customized away from sodium/water costs a
    /// query (one statistics sum, same day bounds as the summary).
    private static func trackedTotals() async -> [Double] {
        var totals: [Double] = [0, 0]
        for slot in 1...2 {
            switch SharedStore.trackedNutrient(slot: slot) {
            case nil, .sodium?, .water?: break
            case .some(let nutrient):
                totals[slot - 1] = (try? await HealthKitService().dayTotal(of: nutrient)) ?? 0
            }
        }
        return totals
    }

    private static let lastGoodKey = "widget.lastGoodSnapshot"
}
