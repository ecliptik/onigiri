import SwiftUI
import SwiftData
import UIKit
import OnigiriKit

enum AppTab: Hashable {
    case today, foods, goal, calendar
    /// The detached corner "+" (the system search-tab slot, Music-style).
    /// Never stays selected — ContentView bounces it and routes.
    case log
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
    @State private var quickActions = QuickActions.shared
    @State private var tabBarPin = TabBarPin.shared
    @AppStorage(SharedStore.hasOnboardedKey, store: SharedStore.defaults) private var hasOnboarded = false
    /// Holds the HKObserverQuery alive for the app's lifetime — a log
    /// arriving from the watch (or any app) refreshes the widgets, which
    /// otherwise stay stale until the next timeline turn or app open.
    @State private var logObserver = HealthKitService()
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
            logObserver.startObservingLogChanges {
                // Debounced funnel: one meal writes a burst of samples (and
                // the observer covers watch/third-party logs too) — coalesce
                // them into a single kind-scoped reload.
                Task { @MainActor in
                    ToastCenter.shared.noteHealthWrite()
                    WidgetReloader.requestReload(kinds: WidgetKinds.phoneLogAffected)
                    // A background wake can suspend before a debounced
                    // flush would run — reload before the window closes.
                    if UIApplication.shared.applicationState != .active {
                        WidgetReloader.flushNow()
                    }
                }
            }
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
            } else {
                // Leaving the foreground: run pending debounced work now —
                // a suspended process never runs its sleeping flush tasks.
                PhoneSyncService.shared.flushNow()
                WidgetReloader.flushNow()
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
                FoodsView()
            }
            Tab("Goal", systemImage: "chart.line.downtrend.xyaxis", value: .goal) {
                GoalView()
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }
            // The Music-style detached corner circle (the search-tab
            // slot is the only public API that renders there). It acts
            // as a button: the onChange below bounces the selection and
            // opens the right add flow for the tab the user was on.
            // "Add", not "Log" — the portion sheet's confirm is "Log"
            // and two same-named buttons make tests (and VoiceOver)
            // ambiguous.
            Tab("Add", systemImage: "plus", value: .log, role: .search) {
                Color.clear
            }
        }
        .tint(.riceToast)
        .onChange(of: selectedTab) { old, new in
            guard new == .log else { return }
            selectedTab = old == .log ? .today : old
            if old == .foods {
                // The Library's +: straight to the new-food form.
                QuickActions.shared.addFoodRequest = true
            } else {
                // Everywhere else: the Log sheet (search-first, scanner
                // and favorites inside).
                selectedTab = .today
                QuickActions.shared.quickLogRequest = .all
            }
        }
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
            // The Log sheet's scanner (library fast path + logging),
            // not the Foods-tab new-food form.
            selectedTab = .today
            QuickActions.shared.quickLogRequest = .scan
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
