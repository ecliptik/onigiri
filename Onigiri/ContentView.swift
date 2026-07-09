import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

enum AppTab: Hashable {
    case today, foods, water, goal, calendar
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .today
    @State private var scanRequest = false
    @State private var quickActions = QuickActions.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "gauge.with.needle", value: .today) {
                TodayView()
            }
            Tab("Foods", systemImage: "fork.knife", value: .foods) {
                FoodsView(scanRequest: $scanRequest)
            }
            Tab("Water", systemImage: "drop.fill", value: .water) {
                WaterView()
            }
            Tab("Goal", systemImage: "chart.line.downtrend.xyaxis", value: .goal) {
                GoalView()
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
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
            // A quick action may have launched the app before this view existed.
            if let action = quickActions.pending {
                quickActions.pending = nil
                handle(action)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PhoneSyncService.shared.push(from: context)
            }
        }
        .onChange(of: quickActions.pending) { _, action in
            guard let action else { return }
            quickActions.pending = nil
            handle(action)
        }
    }

    private func handle(_ action: QuickActions.Action) {
        switch action {
        case .logWater:
            selectedTab = .water
            Task {
                try? await HealthKitService().logWater(oz: SharedStore.waterServingOz)
                WidgetCenter.shared.reloadAllTimelines()
            }
        case .logMeal:
            selectedTab = .foods
        case .scanBarcode:
            selectedTab = .foods
            scanRequest = true
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
