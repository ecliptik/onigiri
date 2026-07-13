import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

enum AppTab: Hashable {
    case today, foods, goal, calendar
}

/// The visible screen reports whether it's scrolled to the top; while it
/// is, the tab bar is pinned expanded. The system re-expands only on an
/// upward scroll GESTURE — collapsing log sections shrinks the content
/// with no gesture, stranding a minimized bar at the very top.
@Observable
@MainActor
final class TabBarPin {
    static let shared = TabBarPin()
    var atTop = true
}

extension View {
    /// Attach to a screen's root scroll container: reports its at-top
    /// state so the tab bar is always full when there's nowhere left to
    /// scroll up (see TabBarPin).
    func expandsTabBarAtTop() -> some View {
        onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top <= 1
        } action: { _, atTop in
            TabBarPin.shared.atTop = atTop
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .today
    @State private var scanRequest = false
    @State private var quickActions = QuickActions.shared
    @State private var tabBarPin = TabBarPin.shared
    @AppStorage(SharedStore.hasOnboardedKey, store: SharedStore.defaults) private var hasOnboarded = false
    /// Latched in the task below: once onboarding is showing, saving a
    /// goal mid-flow must NOT dismiss it (only finish/skip does, via
    /// hasOnboarded) — gating live on goals.isEmpty cut the flow short
    /// the moment the goal page saved.
    @State private var showingOnboarding = false

    var body: some View {
        // The Group keeps the launch tasks alive in BOTH branches —
        // rendering onboarding INSTEAD of the tabs (not over them) also
        // keeps TodayView from firing the Health prompt contextlessly.
        Group {
            if showingOnboarding && !hasOnboarded {
                OnboardingView()
            } else {
                mainTabs
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--seed-sample-data") {
                DebugSeeder.seedLibraryIfEmpty(context: context)
            }
            #endif
            PhoneSyncService.shared.activate {
                PhoneSyncService.shared.push(from: context)
            }
            BackupService.backupIfDue(context: context)
            ReminderScheduler.shared.activate()
            // Existing installs never see onboarding: a goal means the
            // app is already set up. Fresh installs latch it on. The
            // context is asked directly — the seeder just ran in this
            // same task, ahead of any @Query refresh.
            if !hasOnboarded {
                let goalCount = (try? context.fetchCount(FetchDescriptor<GoalSettings>())) ?? 0
                if goalCount > 0 {
                    hasOnboarded = true
                } else {
                    showingOnboarding = true
                }
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
                BackupService.backupIfDue(context: context)
                // Reminders replan from fresh state on every foreground —
                // logging elsewhere (watch, Health) can't notify us.
                ReminderScheduler.shared.replan()
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
        .onChange(of: quickActions.dayRequest) { _, day in
            // Calendar's "View day": land on Today, which consumes the date.
            if day != nil { selectedTab = .today }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            // Today sits first and is the app's home; water lives inside it
            // (hydration row + a Water group in the log).
            Tab("Today", systemImage: "gauge.with.needle", value: .today) {
                TodayView()
            }
            Tab("Foods", systemImage: "fork.knife", value: .foods) {
                FoodsView(scanRequest: $scanRequest)
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
        // content, re-expanding on scroll-up — and pinned full whenever
        // the screen is at the top (the system misses gesture-less
        // returns to the top, like collapsing the log sections).
        .tabBarMinimizeBehavior(tabBarPin.atTop ? .never : .onScrollDown)
        .toastHost()
    }

    private func handle(_ action: QuickActions.Action) {
        switch action {
        case .logWater:
            // Water lives on Today now; LogActions handles the feedback
            // and Today refreshes via the mutation counter.
            selectedTab = .today
            Task {
                await LogActions.logWater(oz: SharedStore.waterServingOz)
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
