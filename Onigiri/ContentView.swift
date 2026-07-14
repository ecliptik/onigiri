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
        modifier(ExpandsTabBarAtTop())
    }
}

/// EVERY pin commit defers to scroll-idle while a gesture is in flight:
/// flipping tabBarMinimizeBehavior re-renders the TabView, and doing it
/// mid-gesture was the "sticky" scroll — first the leave-the-top flip
/// (Foods, 2026-07-13), then the reach-the-top flip, which fired
/// repeatedly DURING the large-title collapse/expand because the title
/// transition shifts contentInsets and oscillates the at-top boundary
/// (Today/Goal, the user, 2026-07-14). Gesture-less at-top changes
/// (collapsing the log sections — the whole reason TabBarPin exists)
/// still commit immediately: no phases fire without a gesture, so idle
/// would never come. Trade-off unchanged: the bar doesn't minimize
/// during the first downward scroll from the top.
private struct ExpandsTabBarAtTop: ViewModifier {
    @State private var atTopNow = true
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top <= 1
            } action: { _, atTop in
                atTopNow = atTop
                if atTop, !isScrolling {
                    Self.commit(true)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                isScrolling = newPhase != .idle
                if newPhase == .idle {
                    Self.commit(atTopNow)
                }
            }
    }

    /// @Observable fires on EVERY set, equal value or not — and each
    /// fire re-evaluates the TabView, which can cancel an in-flight
    /// scroll gesture. Unguarded, sitting at the top turned every swipe
    /// attempt into an invalidation storm (dead swipes on Today after a
    /// day jump — the user, 2026-07-14). Commit only actual changes.
    private static func commit(_ atTop: Bool) {
        if TabBarPin.shared.atTop != atTop {
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
            // The reset-roundtrip UI test's import path: the system file
            // picker is unscriptable enough that the test restores the
            // newest Documents/Backups file at launch instead. Runs
            // before the onboarding check below, so a restored goal
            // latches hasOnboarded exactly like an existing install.
            if ProcessInfo.processInfo.arguments.contains("--import-latest-backup"),
               let url = BackupService.latestBackup(),
               let data = try? Data(contentsOf: url) {
                _ = try? LibraryTransfer.importData(data, into: context)
            }
            #endif
            PhoneSyncService.shared.activate {
                PhoneSyncService.shared.push(from: context)
            }
            BackupService.backupIfDue(context: context)
            ReminderScheduler.shared.activate()
            // (The HealthKit log observer lives in OnigiriApp.init now —
            // a background relaunch never runs this .task.)
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
            // Deferred one turn: bouncing synchronously mid-transition
            // aborts the search-role slot's own activation halfway and
            // leaves the ORIGIN tab's search drawer wedged — dead taps
            // on Foods' search after using the pill (the user; pinned
            // by testFoodsSearchAfterSave).
            Task {
                selectedTab = old == .log ? .today : old
                if old == .foods {
                    // The Library's +: straight to the new-food form.
                    QuickActions.shared.addFoodRequest = true
                } else {
                    // Everywhere else: the Log sheet (search-first,
                    // scanner and favorites inside).
                    selectedTab = .today
                    QuickActions.shared.quickLogRequest = .all
                }
            }
        }
        // Liquid Glass: the tab bar shrinks out of the way while scrolling
        // content, re-expanding on scroll-up — and pinned full whenever
        // the screen is at the top (the system misses gesture-less
        // returns to the top, like collapsing the log sections).
        // iOS 18 bars never minimize; there is nothing to pin.
        .modifier(TabBarMinimizePin(atTop: tabBarPin.atTop))
        // Hold the corner + to log a water serving without the sheet —
        // the tap keeps opening the add flow. Checked at fire time so
        // the Settings toggle applies without a relaunch.
        .background(AddPillLongPress {
            guard SharedStore.holdToLogWater else { return }
            Task { await LogActions.logWater(oz: SharedStore.waterServingOz) }
        })
        .toastHost()
    }

    private struct TabBarMinimizePin: ViewModifier {
        let atTop: Bool

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.tabBarMinimizeBehavior(atTop ? .never : .onScrollDown)
            } else {
                content
            }
        }
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
