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
            .onChange(of: scenePhase) { _, phase in
                // Wrist-down right after logging: run the pending reload
                // now — a suspended app never runs its sleeping flush task.
                if phase != .active {
                    WidgetReloader.flushNow()
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
    }
}
