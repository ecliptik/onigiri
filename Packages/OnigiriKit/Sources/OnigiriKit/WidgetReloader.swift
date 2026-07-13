#if canImport(WidgetKit) && canImport(HealthKit)
import Foundation
import WidgetKit

/// Every widget kind in both bundles, so reloads can be scoped to the
/// widgets an event can actually change.
public enum WidgetKinds {
    // iPhone widgets.
    public static let gauge = "OnigiriGauge"
    public static let waterAccessory = "OnigiriWaterAccessory"
    public static let streak = "OnigiriStreak" // also the watch streak complication
    public static let month = "OnigiriMonth"
    public static let meter = "OnigiriMeter"
    public static let trend = "OnigiriTrend"
    public static let progress = "OnigiriProgress"
    // Watch complications.
    public static let balance = "OnigiriBalance"
    public static let water = "OnigiriWater"
    public static let summary = "OnigiriSummary"

    /// Phone widgets a food/water log can change — everything but the
    /// weigh-in trend chart (which polls on its own).
    public static let phoneLogAffected = [gauge, waterAccessory, streak, month, meter, progress]
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
        pendingKinds.formUnion(kinds)
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
