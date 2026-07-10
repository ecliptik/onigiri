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
        // Liquid Glass: the tab bar shrinks out of the way while scrolling
        // content, re-expanding on scroll-up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .toastHost()
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
                // Belt and braces: consume any shortcut that arrived while no
                // onChange observer was installed yet (cold-launch timing).
                if let action = quickActions.pending {
                    quickActions.pending = nil
                    handle(action)
                }
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
            // Log before switching so the Water tab's on-appear refresh
            // already sees the new serving; LogActions handles feedback.
            Task {
                await LogActions.logWater(oz: SharedStore.waterServingOz)
                selectedTab = .water
            }
        case .logMeal:
            // Land on Today with the quick-log sheet up: one tap to log.
            selectedTab = .today
            QuickActions.shared.quickLogRequest = .meals
        case .logFood:
            selectedTab = .today
            QuickActions.shared.quickLogRequest = .foods
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
