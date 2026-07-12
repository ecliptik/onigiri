import SwiftUI

@main
struct OnigiriWatchApp: App {
    /// One model for both pages — the metrics page reads the same
    /// refresh the home page drives.
    @State private var model = WatchModel()

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
        }
    }
}
