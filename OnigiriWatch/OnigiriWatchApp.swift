import SwiftUI
import WatchKit
import OnigiriKit

@main
struct OnigiriWatchApp: App {
    /// One model for both pages — the metrics page reads the same
    /// refresh the home page drives.
    @State private var model: WatchModel
    /// Holds the HKObserverQuery alive for the app's lifetime — a log
    /// arriving from the phone refreshes the complications, which
    /// otherwise stay stale until the next timeline turn or app open.
    @State private var logObserver: HealthKitService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Session activation and the log observer belong to the PROCESS,
        // not a page: a background wake (queued WC context, HealthKit
        // background delivery) may never run any view's .task, and an
        // unactivated session never delivers the phone's pushes.
        let model = WatchModel()
        model.sync.activate()
        let observer = HealthKitService()
        observer.startObservingLogChanges { [model] in
            // Debounced funnel: one meal writes a burst of samples (and
            // phone logs sync in as bursts too) — coalesce them into a
            // single complication reload. Runs before the observer
            // completes, so a background wake can't suspend under it.
            let isActive = await MainActor.run {
                WidgetReloader.requestReload(kinds: WidgetKinds.watchAll)
                let active = WKApplication.shared().applicationState == .active
                // A background wake suspends after completion — flush
                // the debounce before the window closes.
                if !active { WidgetReloader.flushNow() }
                return active
            }
            // Foreground: the changed samples just landed in OUR HealthKit
            // store — this is the phone's log/edit/undo arriving via
            // HealthKit's own device sync. Pull them into the open headline
            // now instead of stranding it until the next wrist-raise or
            // page swipe (the observer otherwise only refreshes the
            // complications, never the app's total). maxAge 0 forces a
            // fresh read but still joins an in-flight refresh, so a burst
            // of sample writes coalesces into one query set.
            if isActive { await model.refreshIfStale(maxAge: 0) }
        }
        // Today's ACTIVE energy — the only input that moves the day's
        // budget between midnight and bedtime, and the one nothing
        // observed until 2026-08-03. Registered here even though watchOS
        // caps its delivery (see startObservingBurnChanges): when the
        // watch app IS running, this fires live and costs nothing, and
        // if the cap turns out not to apply to active energy the
        // complications get the phone's cadence for free. The scheduled
        // wake in WatchBackgroundRefresh is what carries the cadence
        // when it does apply.
        observer.startObservingBurnChanges {
            let reloaded = await BurnWidgetRefresh.refreshIfBurnMoved(
                kinds: WidgetKinds.watchBurnAffected
            )
            if reloaded {
                await MainActor.run {
                    if WKApplication.shared().applicationState != .active {
                        WidgetReloader.flushNow()
                    }
                }
            }
        }
        // NOTE the wake chain is armed from the SCENE below, never here.
        // `WKApplication.shared()` during App.init reaches for an
        // application object that does not exist yet — the app failed to
        // launch at all (2026-08-03, caught on device the same day it was
        // added). Observers are fine in init; anything that touches
        // WKApplication is not.
        _model = State(initialValue: model)
        _logObserver = State(initialValue: observer)
    }

    var body: some Scene {
        WindowGroup {
            // Horizontal pages: home (headline + quick log buttons,
            // always immediate on open), Metrics, today's Log (edit or
            // remove entries). watchOS's default TabView style IS
            // horizontal paging with dots, so the pages' own vertical
            // scrolling stays crown-friendly.
            TabView {
                WatchHomeView(model: model)
                WatchMetricsView(model: model)
                WatchLogView(model: model)
                // The Favorites/Meals/Foods browse pages were dropped
                // (batch D): they duplicated the meal-picker sheet one
                // tap from Home, and six pages is past the 2-5 watchOS
                // guideline — "Foods" was five swipes away.
            }
            // Arm the burn wake chain once the scene is actually up.
            // `.task`, not `init`: scheduling needs a live WKApplication,
            // and onChange alone would never fire for the FIRST
            // activation, leaving the chain unarmed until the app was
            // opened and closed once.
            .task { WatchBackgroundRefresh.schedule() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Explicitly, like the phone's ContentView: nothing
                    // else reloads the complications on foreground.
                    // WatchModel refreshes the APP's numbers on every
                    // wrist raise, which is why the app was right while
                    // the complications beside it were not. Throttled
                    // inside WidgetReloader.
                    WidgetReloader.requestForegroundReload(kinds: WidgetKinds.watchAll)
                } else {
                    // Wrist-down right after logging: run the pending
                    // reload now — a suspended app never runs its
                    // sleeping flush task.
                    WidgetReloader.flushNow()
                    // …and make sure a wake is armed for while we're gone.
                    WatchBackgroundRefresh.schedule()
                }
            }
            // The dock snapshot otherwise shows the calorie headline —
            // the phone's PrivacyShield, watch-sized. A root overlay is
            // the best watchOS offers (no window layer to hook), so
            // sheet content stays uncovered; acceptable for dock cards
            // (2026-07-20 security audit).
            .overlay {
                if scenePhase != .active {
                    WatchPrivacyShield()
                }
            }
        }
        // The phone pushes library/goal changes as applicationContext;
        // without this handler a suspended watch app never receives them
        // and the complications render the old plan until the app is
        // manually opened.
        .backgroundTask(.watchConnectivity) {
            await model.sync.receiveQueuedContext()
        }
        // The scheduled burn wake (Phase 2b). On watchOS the bare
        // `.appRefresh` hands the closure the scheduled userInfo as a
        // String? — it is not the identifier form iOS uses.
        .backgroundTask(.appRefresh) { _ in
            await WatchBackgroundRefresh.handleWake()
        }
    }
}

/// Dock-snapshot cover — the mascot on the watch's black, none of the
/// numbers (the phone shield's sibling).
private struct WatchPrivacyShield: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("🍙")
                .font(.system(size: 40))
                .accessibilityHidden(true)
        }
    }
}
