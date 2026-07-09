import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            Tab("Today", systemImage: "gauge.with.needle") {
                TodayView()
            }
            Tab("Foods", systemImage: "fork.knife") {
                FoodsView()
            }
            Tab("Water", systemImage: "drop.fill") {
                PlaceholderView(
                    title: "Water",
                    systemImage: "drop.fill",
                    detail: "Quick-add servings toward your daily water goal."
                )
            }
            Tab("Goal", systemImage: "chart.line.downtrend.xyaxis") {
                GoalView()
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
                DebugSeeder.seedLibraryIfEmpty(context: context)
            }
            #endif
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
