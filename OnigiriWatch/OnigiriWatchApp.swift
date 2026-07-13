import SwiftUI
import WidgetKit
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

    var body: some Scene {
        WindowGroup {
            // Horizontal pages: home (headline + quick log buttons,
            // always immediate on open), Metrics, then the three browse
            // pages mirroring the phone Log sheet's scopes. watchOS's
            // default TabView style IS horizontal paging with dots, so
            // the pages' own vertical scrolling stays crown-friendly.
            TabView {
                WatchHomeView(model: model)
                WatchMetricsView(model: model)
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
                    Task { @MainActor in
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }
    }
}
