import Foundation

#if canImport(os)
import os

/// Timeline instrumentation (PLAN-widget-burn-freshness, Phase 0). Every
/// provider in both bundles logs the moment it builds a timeline and the
/// day burn it rendered, so the real reload cadence can be read off a
/// device day with `log collect` instead of guessed at.
public enum WidgetLog {
    public static let timeline = Logger(
        subsystem: "com.ecliptik.Onigiri", category: "widget.timeline"
    )

    /// One line per `getTimeline`: which kind, what it rendered, when it
    /// asked to be woken again, and whether it was serving a cached
    /// snapshot because the Health store was sealed.
    public static func timelineBuilt(
        kind: String, dayBurnKcal: Double?, nextPoll: TimeInterval, cached: Bool
    ) {
        // The SHAPE of the timeline is public — which provider, how far
        // out the next poll is, whether it came from cache. The kcal is
        // not: it is a measured HealthKit figure about the person using
        // the app, and this line fires on every timeline build, so
        // leaving it public wrote a running record of their energy burn
        // into a log any sysdiagnose carries off the device.
        //
        // Numeric interpolations default to public, so this needs saying
        // explicitly rather than merely leaving the annotation off. A
        // debugger still shows it, which is where it was ever read.
        timeline.notice("""
            timeline kind=\(kind, privacy: .public) \
            dayBurn=\(dayBurnKcal ?? -1, format: .fixed(precision: 0), privacy: .private) \
            nextPollMin=\(nextPoll / 60, format: .fixed(precision: 1), privacy: .public) \
            cached=\(cached, privacy: .public)
            """)
    }

    /// One line per burn-observer fire, gate verdict included — this is
    /// what says whether `.immediate` delivery is honored or capped.
    public static func burnObserved(activeKcal: Double, lastRendered: Double?, reloading: Bool) {
        // `reloading` is the gate VERDICT and stays public — it is the
        // whole diagnostic point of this line (PLAN-widget-burn-freshness).
        // The two kcal readings behind it are health data.
        timeline.notice("""
            burn active=\(activeKcal, format: .fixed(precision: 0), privacy: .private) \
            lastRendered=\(lastRendered ?? -1, format: .fixed(precision: 0), privacy: .private) \
            reloading=\(reloading, privacy: .public)
            """)
    }
}
#endif

/// Shared timeline policy: the observer-driven funnel is what keeps
/// widgets fresh; providers poll only as a fallback. Outside the
/// WidgetKit guard so the pure test host reaches `nextPoll`.
public enum WidgetRefreshPolicy {
    /// The old flat fallback, kept as the overnight interval and as the
    /// name every provider's "no signal" branch still reads.
    public static let pollFallback: TimeInterval = 60 * 60

    // MARK: - Waking-hours cadence

    /// A day's poll is worth more between breakfast and bedtime than it
    /// is at 03:00. Splitting the cadence buys ~1.3× the daytime
    /// freshness for FEWER total reloads than a flat hour: ~21 daytime
    /// (16 h ÷ 45 min) + ~3 overnight ≈ 24/day, the same spend, aimed
    /// where the number actually moves. Deliberately well inside
    /// WidgetKit's ~40–70/day budget, because Phase 2's burn reloads
    /// draw on the same pool.
    public static let wakingPoll: TimeInterval = 45 * 60
    public static let sleepingPoll: TimeInterval = 3 * 60 * 60
    /// Waking hours, local: [start, end).
    public static let wakingStartHour = 7
    public static let wakingEndHour = 23

    public static func isWakingHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= wakingStartHour && hour < wakingEndHour
    }

    /// The baseline poll for a timeline built now.
    public static func pollInterval(now: Date = .now, calendar: Calendar = .current) -> TimeInterval {
        isWakingHour(now, calendar: calendar) ? wakingPoll : sleepingPoll
    }

    // MARK: - Recent-activity window

    /// A phone log just synced its stamp over WatchConnectivity, but the
    /// sample itself rides HealthKit's slower device sync — the reload
    /// the stamp triggered may have read pre-log totals. Poll again soon
    /// while inside the window; the second read catches the sample.
    ///
    /// Renamed off "post-log" 2026-08-03: burn now opens this window
    /// too. It was only ever pointed at food because food was the only
    /// thing anything stamped, which is exactly why a walk left every
    /// complication on the flat hourly fallback.
    public static let recentActivityPoll: TimeInterval = 8 * 60
    public static let recentActivityWindow: TimeInterval = 20 * 60

    /// The providers' next poll interval: short after recent activity
    /// (a log, or burn that moved enough to matter), the waking-hours
    /// cadence otherwise. `abs` so a device-clock skew can't turn a
    /// just-written stamp into "stale".
    public static func nextPoll(
        now: Date = .now, lastActivityAt: Date?, calendar: Calendar = .current
    ) -> TimeInterval {
        guard let lastActivityAt,
              abs(now.timeIntervalSince(lastActivityAt)) < recentActivityWindow
        else { return pollInterval(now: now, calendar: calendar) }
        return recentActivityPoll
    }

    // MARK: - Sealed store

    /// A timeline built against a locked device serves a known-stale
    /// cached snapshot. Committing the full cadence on top of that is
    /// what turned a pocketed phone into an afternoon of yesterday's
    /// number — retry soon instead.
    public static let sealedStoreRetry: TimeInterval = 10 * 60

    // MARK: - Burn gate

    /// How far the day's active energy must move before a reload is
    /// worth a slot of the reload budget. ~40 kcal is roughly ten
    /// minutes' brisk walking — small enough to feel responsive, large
    /// enough that a resting drip can't drain the budget.
    public static let burnDeltaKcal: Double = 40
    /// Floor between burn-driven reloads, whatever the delta.
    public static let burnReloadInterval: TimeInterval = 10 * 60

    /// The gate every burn observer runs before spending a reload.
    ///
    /// Active energy ALONE is the input, not the whole day burn: within a
    /// day `DayBudget.dayBurn` is `active + max(resting, estimate)`, and
    /// the resting term is flat (held at the full-day estimate until
    /// measured resting overtakes it). So active is the only fast-moving
    /// term, and reading it costs one statistics query instead of the
    /// plan's whole pipeline.
    ///
    /// `nil` last-rendered means the widget has never recorded a render
    /// today — reload, so a fresh day or a fresh install lands a real
    /// number instead of waiting out a delta it can't measure.
    public static func shouldReloadForBurn(
        activeKcal: Double,
        lastRenderedActiveKcal: Double?,
        lastReloadAt: Date?,
        now: Date = .now
    ) -> Bool {
        if let lastReloadAt, abs(now.timeIntervalSince(lastReloadAt)) < burnReloadInterval {
            return false
        }
        guard let lastRenderedActiveKcal else { return true }
        return activeKcal - lastRenderedActiveKcal >= burnDeltaKcal
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
    /// Phone widgets a BURN change can move: the budget-shaped ones.
    /// Water is untouched by burn, and the streak/month surfaces judge
    /// COMPLETED days — today's burn can't change either until midnight.
    public static let phoneBurnAffected = [gauge, todayCard]
    /// Watch complications a log can change (all of them).
    public static let watchAll = [balance, water, streak, summary]
    /// Watch complications a burn change can move — same reasoning as
    /// the phone's: the balance headline and the summary card.
    public static let watchBurnAffected = [balance, summary]
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

    /// Foreground entry point (PLAN-widget-burn-freshness, Phase 1).
    ///
    /// Opening the app used to reload widgets only as a SIDE EFFECT of
    /// the watch-sync push, which skips when the payload fingerprint is
    /// unchanged — and those fingerprints are per-process, so a cold
    /// launch reloaded and a warm foreground reloaded NOTHING. The one
    /// workaround the user had ("just open the app") therefore worked or
    /// didn't depending on whether iOS had kept the process alive.
    /// Throttled, because a scene can activate on every tab flip and
    /// wrist raise.
    public static let foregroundThrottle: TimeInterval = 3 * 60
    private static var lastForegroundReload: Date?

    public static func requestForegroundReload(kinds: [String], now: Date = .now) {
        if let last = lastForegroundReload, now.timeIntervalSince(last) < foregroundThrottle {
            return
        }
        lastForegroundReload = now
        requestReload(kinds: kinds)
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
