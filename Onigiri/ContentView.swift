import SwiftUI
import SwiftData
import OnigiriKit

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
                WaterView()
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

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
