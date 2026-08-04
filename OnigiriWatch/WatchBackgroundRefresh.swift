import Foundation
import WatchKit
import OnigiriKit

/// The watch's answer to the hourly background-delivery cap
/// (PLAN-widget-burn-freshness, Phase 2b).
///
/// The phone can lean on HealthKit's `.immediate` background delivery for
/// active energy; watchOS silently caps most types at hourly whatever is
/// asked for, so an observer alone would leave the complications on
/// roughly the same cadence as the poll they already had. Instead the
/// watch schedules its OWN wake-ups: watchOS grants a materially better
/// app-refresh allowance to an app with a complication on the active
/// face, and this is the standard way a complication stays current
/// between timeline turns. Onigiri declared only
/// `.backgroundTask(.watchConnectivity)` and never used it.
///
/// The irony this closes: the watch is where active energy ORIGINATES —
/// its store holds the samples before HealthKit's device sync carries
/// them to the phone — yet it had the stalest surface and the tightest
/// delivery cap.
///
/// Deliberately the legacy `WKApplication` scheduling call, not
/// `BGTaskScheduler`: BackgroundTasks reached watchOS at 26 and this
/// target's floor is watchOS 10 (project.yml). Revisit if the floor ever
/// rises past 26 — the replacement is `BGAppRefreshTaskRequest` plus a
/// `BGTaskSchedulerPermittedIdentifiers` entry.
@MainActor
enum WatchBackgroundRefresh {
    /// Rides through as the task's `userInfo` so the handler can tell
    /// this flow from any future one.
    static let reason = "burn-refresh"

    /// Requested spacing. watchOS decides what it actually grants; this
    /// is a preference, not a guarantee. Short enough that a walk shows
    /// up while it still feels like the same walk, long enough that the
    /// gate — not the schedule — is what bounds the reload spend.
    static let interval: TimeInterval = 20 * 60

    static func schedule(after delay: TimeInterval = interval) {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: delay),
            userInfo: reason as NSString
        ) { error in
            if let error {
                print("Onigiri: watch background refresh not scheduled: \(error)")
            }
        }
    }

    /// One wake: run the shared burn gate, flush if it spent a reload,
    /// and re-arm.
    ///
    /// **Re-arm unconditionally**, including when the gate blocks. A
    /// chain that only re-armed on a reload would die silently the first
    /// quiet hour — one still afternoon and the complications would be
    /// back to the plain poll until the app was next opened, with
    /// nothing in the logs to say so.
    static func handleWake() async {
        let reloaded = await BurnWidgetRefresh.refreshIfBurnMoved(
            kinds: WidgetKinds.watchBurnAffected
        )
        // This wake ends in suspension the moment the handler returns —
        // a debounced reload left sleeping would die with it.
        if reloaded {
            WidgetReloader.flushNow()
        }
        schedule()
    }
}
