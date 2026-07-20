import Foundation

/// Shared timeline policy: the observer-driven funnel is what keeps
/// widgets fresh; providers poll only as a fallback. Outside the
/// WidgetKit guard so the pure test host reaches `nextPoll`.
public enum WidgetRefreshPolicy {
    public static let pollFallback: TimeInterval = 60 * 60
    /// A phone log just synced its stamp over WatchConnectivity, but the
    /// sample itself rides HealthKit's slower device sync — the reload
    /// the stamp triggered may have read pre-log totals. Poll again soon
    /// while inside the window; the second read catches the sample.
    public static let postLogPoll: TimeInterval = 8 * 60
    public static let postLogWindow: TimeInterval = 20 * 60

    /// The watch providers' next poll interval: short after a fresh phone
    /// log stamp, the hourly fallback otherwise. `abs` so a device-clock
    /// skew can't turn a just-written stamp into "stale".
    public static func nextPoll(now: Date = .now, lastLogAt: Date?) -> TimeInterval {
        guard let lastLogAt, abs(now.timeIntervalSince(lastLogAt)) < postLogWindow
        else { return pollFallback }
        return postLogPoll
    }
}

#if canImport(WidgetKit) && canImport(HealthKit)
import WidgetKit

/// Every widget kind in both bundles, so reloads can be scoped to the
/// widgets an event can actually change.
public enum WidgetKinds {
    // iPhone widgets. (Meter/Progress/Month removed 2.1 — the user
    // trimmed the lineup to the Today card + gauge/water/streak/trend.)
    public static let gauge = "OnigiriGauge"
    public static let waterAccessory = "OnigiriWaterAccessory"
    public static let streak = "OnigiriStreak" // also the watch streak complication
    public static let monthStats = "OnigiriMonthStats"
    public static let todayCard = "OnigiriTodayCard"
    // Watch complications.
    public static let balance = "OnigiriBalance"
    public static let water = "OnigiriWater"
    public static let summary = "OnigiriSummary"

    /// Phone widgets a food/water log can change — everything but the
    /// weigh-in trend chart (which polls on its own).
    public static let phoneLogAffected = [gauge, waterAccessory, streak, monthStats, todayCard]
    /// Watch complications a log can change (all of them).
    public static let watchAll = [balance, water, streak, summary]
}

/// The single funnel for widget reloads. A log used to fire
/// reloadAllTimelines two or three times back-to-back (mutation handler,
/// sync push, HealthKit observer), each fanning out to every provider's
/// full query stack. Requests here coalesce into one reload after a short
/// trailing window, and PlanCache is invalidated exactly once per flush.
@MainActor
public enum WidgetReloader {
    private static var pendingKinds: Set<String> = []
    private static var pendingAll = false
    private static var flushTask: Task<Void, Never>?

    /// Coalescing window: long enough to absorb one meal's burst of
    /// samples (and the observer echo of a direct request), short enough
    /// that widgets still feel instant.
    public static let debounce: Duration = .seconds(2)

    public static func requestReload(kinds: [String]) {
        // Cross-process echo guard: an interactive intent (widget
        // process) already reloaded its kinds directly; the same
        // HealthKit write then wakes the app, whose observer lands
        // here — the in-memory debounce can't see across processes,
        // so every widget tap was paying a second full reload burst.
        let skip = recentDirectKinds()
        let wanted = kinds.filter { !skip.contains($0) }
        guard !wanted.isEmpty else { return }
        pendingKinds.formUnion(wanted)
        schedule()
    }

    public static func requestReloadAll() {
        pendingAll = true
        schedule()
    }

    /// Immediate, for short-lived processes (App Intents in the widget
    /// extension) that may be killed before a debounced flush could run.
    public static func reloadNow(kinds: [String]) {
        PlanCache.invalidate()
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        // Stamp AFTER the reloads: if the extension dies mid-intent the
        // observer echo still covers the write.
        SharedStore.defaults.set(
            ["stamp": Date.now.timeIntervalSince1970, "kinds": kinds] as [String: Any],
            forKey: directStampKey
        )
    }

    private static let directStampKey = "widgetReloader.directReload"
    private static let echoWindow: TimeInterval = 5

    private static func recentDirectKinds() -> Set<String> {
        guard let dict = SharedStore.defaults.dictionary(forKey: directStampKey),
              let stamp = dict["stamp"] as? Double,
              Date.now.timeIntervalSince1970 - stamp < echoWindow,
              let kinds = dict["kinds"] as? [String] else { return [] }
        return Set(kinds)
    }

    /// Run any pending reload immediately. Call when the scene leaves the
    /// foreground: a suspended process never runs a sleeping flush task,
    /// and the reload a log just requested would be silently lost.
    public static func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        guard pendingAll || !pendingKinds.isEmpty else { return }
        flush()
    }

    private static func schedule() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private static func flush() {
        flushTask = nil
        let all = pendingAll
        let kinds = pendingKinds
        pendingAll = false
        pendingKinds = []
        PlanCache.invalidate()
        if all {
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            for kind in kinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }
}
#endif
