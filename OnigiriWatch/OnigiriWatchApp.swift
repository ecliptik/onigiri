import SwiftUI
import WatchKit
import OnigiriKit

@main
struct OnigiriWatchApp: App {
    /// One model for both pages — the metrics page reads the same
    /// refresh the home page drives.
    @State private var model = WatchModel()
    /// Holds the HKObserverQuery alive for the app's lifetime — a log
    /// arriving from the phone refreshes the complications, which
    /// otherwise stay stale until the next timeline turn or app open.
    @State private var logObserver = HealthKitService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Horizontal pages: home (headline + quick log buttons,
            // always immediate on open), Metrics, today's Log (edit or
            // remove entries), then the three browse pages mirroring the
            // phone Log sheet's scopes. watchOS's default TabView style
            // IS horizontal paging with dots, so the pages' own vertical
            // scrolling stays crown-friendly.
            TabView {
                WatchHomeView(model: model)
                WatchMetricsView(model: model)
                WatchLogView(model: model)
                LogScopeView(
                    model: model, title: "Favorites",
                    items: model.sync.favorites,
                    empty: "Favorites from your iPhone appear here."
                )
                LogScopeView(
                    model: model, title: "Meals",
                    items: Array(model.sync.meals.prefix(10)),
                    empty: "Save meals on your iPhone and they'll appear here."
                )
                LogScopeView(
                    model: model, title: "Foods",
                    items: model.sync.recentFoods,
                    empty: "Foods you log on your iPhone appear here."
                )
            }
            .task {
                logObserver.startObservingLogChanges {
                    // Debounced funnel: one meal writes a burst of samples
                    // (and phone logs sync in as bursts too) — coalesce
                    // them into a single complication reload. This also
                    // covers the watch's own logs, which used to reload
                    // directly AND through this observer.
                    Task { @MainActor in
                        WidgetReloader.requestReload(kinds: WidgetKinds.watchAll)
                        // A background wake can suspend before a debounced
                        // flush would run — reload before the window closes.
                        if WKApplication.shared().applicationState != .active {
                            WidgetReloader.flushNow()
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Wrist-down right after logging: run the pending reload
                // now — a suspended app never runs its sleeping flush task.
                if phase != .active {
                    WidgetReloader.flushNow()
                }
            }
        }
    }
}
