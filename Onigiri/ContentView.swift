import SwiftUI
import SwiftData
import OnigiriKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

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
            Tab("Calendar", systemImage: "calendar") {
                CalendarView()
            }
        }
        .tint(.riceToast)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
                DebugSeeder.seedLibraryIfEmpty(context: context)
            }
            #endif
            PhoneSyncService.shared.activate {
                PhoneSyncService.shared.push(from: context)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PhoneSyncService.shared.push(from: context)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
