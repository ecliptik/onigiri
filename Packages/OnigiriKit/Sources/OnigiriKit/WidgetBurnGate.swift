import Foundation

/// App-group state behind the burn gate (PLAN-widget-burn-freshness,
/// Phase 2).
///
/// The problem this exists to solve: `activeEnergyBurned` changes
/// constantly while you move — the watch syncs it in small batches — but
/// WidgetKit grants only ~40–70 reloads a day. Reloading on every sample
/// exhausts the budget by mid-afternoon and the widget then freezes for
/// the rest of the day, which is strictly worse than the staleness it was
/// meant to fix. So the observer fires often and reloads rarely: this
/// records what was last RENDERED, and `WidgetRefreshPolicy
/// .shouldReloadForBurn` decides whether the difference is worth a slot.
///
/// Day-keyed like `TodayBurnFloor`, and for the same reason: active
/// energy resets at midnight, so yesterday's mark would read as a huge
/// negative delta and gate off the whole morning.
///
/// **Per-device by design.** Each device keeps its own mark over its own
/// Health store, exactly as `TodayBurnFloor` does — the watch sees its
/// active energy before the phone does, and syncing the marks would make
/// each device's freshness wait on the other's.
public enum WidgetBurnGate {
    static let renderedDayKey = "widget.renderedActiveDay"
    static let renderedKcalKey = "widget.renderedActiveKcal"
    static let lastReloadKey = "widget.lastBurnReloadAt"
    static let activityKey = "widget.lastBurnActivityAt"

    /// What a widget or complication just rendered. Called from the
    /// widget process on every timeline build, and from the coordinator
    /// when it spends a reload — without the second call, a device with
    /// no widget installed would re-fire the gate every interval forever
    /// (nothing would ever record a baseline).
    public static func recordRendered(
        activeKcal: Double, now: Date = .now, calendar: Calendar = .current
    ) {
        let defaults = SharedStore.defaults
        defaults.set(DeficitTargetHistory.dayKey(for: now, calendar: calendar), forKey: renderedDayKey)
        defaults.set(activeKcal, forKey: renderedKcalKey)
    }

    /// The last rendered active total, or nil when nothing has rendered
    /// today — which the gate reads as "reload, we have no baseline".
    public static func renderedActiveKcal(
        now: Date = .now, calendar: Calendar = .current
    ) -> Double? {
        let defaults = SharedStore.defaults
        guard defaults.string(forKey: renderedDayKey)
            == DeficitTargetHistory.dayKey(for: now, calendar: calendar),
              defaults.object(forKey: renderedKcalKey) != nil
        else { return nil }
        return defaults.double(forKey: renderedKcalKey)
    }

    /// A small, durable record of what the burn gate decided.
    ///
    /// os_log was not enough: a `log collect` run the morning after a
    /// workout covered the full 24 h but held NO Onigiri lines older than
    /// nine hours — Default-level entries roll off a busy device fast, so
    /// the one window worth reading was already gone (2026-08-06). This
    /// survives in the App Group until it ages out by count, and
    /// `diagnoseIntake` prints it, so the question "did the widget
    /// actually follow that workout?" can be answered after the fact
    /// instead of requiring someone to watch a screen at the right moment.
    static let journalKey = "widget.burnJournal"
    private static let journalLimit = 40

    public static func note(activeKcal: Double, lastRendered: Double?, reloading: Bool, at date: Date = .now) {
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm"
        let line = "\(stamp.string(from: date)) active=\(Int(activeKcal))"
            + " last=\(lastRendered.map { String(Int($0)) } ?? "-")"
            + (reloading ? " RELOAD" : "")
        var lines = SharedStore.defaults.stringArray(forKey: journalKey) ?? []
        lines.append(line)
        if lines.count > journalLimit { lines.removeFirst(lines.count - journalLimit) }
        SharedStore.defaults.set(lines, forKey: journalKey)
    }

    public static func journal() -> [String] {
        SharedStore.defaults.stringArray(forKey: journalKey) ?? []
    }

    /// The budget's inputs, every time a plan is computed — app, widget
    /// and watch alike, since they all go through `DailyPlanLoader.load`.
    /// Deduplicated on the value line so an idle hour of identical reads
    /// doesn't push the interesting ones out of a 40-entry window.
    static let planJournalKey = "widget.planJournal"

    public static func notePlan(
        active: Double, restingMeasured: Double, restingEstimate: Double?,
        weight: Double?, at date: Date = .now
    ) {
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm"
        let values = "act=\(Int(active)) restM=\(Int(restingMeasured))"
            + " restE=\(restingEstimate.map { String(Int($0)) } ?? "NIL")"
            + " wt=\(weight.map { String(Int($0)) } ?? "NIL")"
        var lines = SharedStore.defaults.stringArray(forKey: planJournalKey) ?? []
        // Same numbers as last time: refresh the timestamp rather than
        // add a row, so the trail shows CHANGES.
        if let last = lines.last, last.hasSuffix(values) {
            lines[lines.count - 1] = "\(stamp.string(from: date)) \(values)"
        } else {
            lines.append("\(stamp.string(from: date)) \(values)")
        }
        if lines.count > journalLimit { lines.removeFirst(lines.count - journalLimit) }
        SharedStore.defaults.set(lines, forKey: planJournalKey)
    }

    public static func planJournal() -> [String] {
        SharedStore.defaults.stringArray(forKey: planJournalKey) ?? []
    }

    public static func lastBurnReloadAt() -> Date? {
        guard let stamp = SharedStore.defaults.object(forKey: lastReloadKey) as? Double
        else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    public static func noteBurnReload(at date: Date = .now) {
        SharedStore.defaults.set(date.timeIntervalSince1970, forKey: lastReloadKey)
    }

    /// Burn moved enough to matter — opens the providers' short-poll
    /// window, the one that used to open only for food (Phase 3).
    public static func noteActivity(at date: Date = .now) {
        SharedStore.defaults.set(date.timeIntervalSince1970, forKey: activityKey)
    }

    /// The freshest "something moved" stamp, food or burn — what every
    /// provider hands to `WidgetRefreshPolicy.nextPoll`. A phone log
    /// still stamps through `WatchSync.stampPhoneLog` (it also has to
    /// ride the WatchConnectivity payload); burn stamps here. Whichever
    /// is newer wins.
    public static func lastActivityAt() -> Date? {
        let burn = (SharedStore.defaults.object(forKey: activityKey) as? Double)
            .map(Date.init(timeIntervalSince1970:))
        let log = WatchSync.lastPhoneLogAt()
        switch (burn, log) {
        case let (burn?, log?): return max(burn, log)
        case let (burn?, nil): return burn
        case let (nil, log?): return log
        case (nil, nil): return nil
        }
    }
}

#if canImport(WidgetKit) && canImport(HealthKit)

/// The burn observer's handler, shared by both apps.
///
/// Reads today's active energy (ONE statistics query — see
/// `shouldReloadForBurn` for why active alone is the right input), runs
/// the gate, and spends a scoped reload only when it passes.
@MainActor
public enum BurnWidgetRefresh {
    /// - Returns: whether a reload was actually requested, so a caller
    ///   that is about to be suspended knows whether it must flush.
    @discardableResult
    public static func refreshIfBurnMoved(
        kinds: [String],
        health: HealthKitService = HealthKitService(),
        now: Date = .now
    ) async -> Bool {
        // A sealed store (locked device) reads zero, not "unchanged" —
        // and a zero would look like the day reset and gate the reload
        // off for the rest of the window. Bail instead; the next fire
        // after unlock does the real comparison.
        //
        // This is the site the old `isStoreLocked()` failed worst: it
        // passed on a sealed store, read active as 0, and then wrote that
        // zero as the rendered baseline — so the following fire measured
        // a jump that never happened.
        guard await !health.healthReadLooksSealed(now: now) else { return false }
        guard let active = try? await health.todayActiveBurnKcal(now: now) else { return false }
        let lastRendered = WidgetBurnGate.renderedActiveKcal(now: now)
        let shouldReload = WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: active,
            lastRenderedActiveKcal: lastRendered,
            lastReloadAt: WidgetBurnGate.lastBurnReloadAt(),
            now: now
        )
        #if canImport(os)
        WidgetLog.burnObserved(
            activeKcal: active, lastRendered: lastRendered, reloading: shouldReload
        )
        #endif
        WidgetBurnGate.note(
            activeKcal: active, lastRendered: lastRendered, reloading: shouldReload, at: now
        )
        guard shouldReload else { return false }
        WidgetBurnGate.noteBurnReload(at: now)
        WidgetBurnGate.noteActivity(at: now)
        WidgetBurnGate.recordRendered(activeKcal: active, now: now)
        WidgetReloader.requestReload(kinds: kinds)
        return true
    }
}
#endif
