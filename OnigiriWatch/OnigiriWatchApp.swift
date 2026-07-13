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
            // unchanged) and the tracked-metrics page. watchOS's default
            // TabView style IS horizontal paging with dots, so the pages'
            // own vertical scrolling stays crown-friendly.
            TabView {
                WatchHomeView(model: model)
                WatchMetricsView(model: model)
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
