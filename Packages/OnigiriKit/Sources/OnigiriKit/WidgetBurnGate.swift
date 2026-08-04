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
        guard await !health.isStoreLocked() else { return false }
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
        guard shouldReload else { return false }
        WidgetBurnGate.noteBurnReload(at: now)
        WidgetBurnGate.noteActivity(at: now)
        WidgetBurnGate.recordRendered(activeKcal: active, now: now)
        WidgetReloader.requestReload(kinds: kinds)
        return true
    }
}
#endif
