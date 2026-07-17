import SwiftUI
import SwiftData
import UIKit
import OnigiriKit

/// String-backed so @SceneStorage can persist the selection across
/// scene teardowns.
enum AppTab: String, Hashable {
    case today, foods, goal, calendar
    /// The detached corner "+" (the system search-tab slot, Music-style).
    /// Never stays selected — ContentView bounces it and routes.
    case log
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    /// Restored across scene teardowns (iPad multitasking, memory
    /// pressure) so the app reopens on the tab it was left on; a fresh
    /// launch still lands on Today, the app's home.
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .today
    @State private var quickActions = QuickActions.shared
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
        .overlay {
            // The app-switcher snapshot otherwise shows the day's health
            // numbers to anyone flipping through cards. Covered from
            // .inactive on — the snapshot is taken before .background
            // settles. (Also flashes during Control Center pulls; the
            // standard trade for a health app.)
            if scenePhase != .active {
                PrivacyShield()
            }
        }
        .task {
            // Scene restoration can hand back .log (the bounce-only "+"
            // slot) if the snapshot landed mid-bounce; restoring INTO it
            // renders Color.clear and the bounce onChange never fires
            // for an initial value. Land on home instead.
            if selectedTab == .log { selectedTab = .today }
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
        // The Today-card widget's + button: the Log sheet for the day
        // the widget was showing (backfill included). No day parameter
        // means today.
        .onOpenURL { url in
            guard url.scheme == "onigiri" else { return }
            switch url.host() {
            case "log":
                selectedTab = .today
                if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "day" })?.value,
                   let day = Self.deepLinkDay.date(from: raw) {
                    QuickActions.shared.dayRequest = day
                }
                QuickActions.shared.quickLogRequest = .all
            case "calendar":
                // The month-stats widget: land on the Calendar tab, not
                // wherever the app happened to be.
                selectedTab = .calendar
            default:
                break
            }
        }
    }

    private static let deepLinkDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var mainTabs: some View {
        // iPad: the top tab bar can become a sidebar at the user's
        // choice (no effect on iPhone's bottom bar).
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
        // iPad: the tab bar can become a sidebar at the user's choice
        // (top-bar toggle); no effect on iPhone's bottom bar.
        .tabViewStyle(.sidebarAdaptable)
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
        // content, re-expanding on scroll-up. Constant .onScrollDown, not
        // flipped to .never at the top: the flip committed "left the top"
        // only at scroll-idle, so the FIRST scroll from the top never
        // minimized — worst on Foods/Goal, where you scroll once and stop,
        // so it read as "never minimizes" (the user, 2026-07-16). Trade-off:
        // after a gesture-less collapse of Today's log while scrolled, the
        // bar can sit minimized until the next scroll. iOS 18 bars never
        // minimize; the modifier is a no-op there.
        .modifier(TabBarMinimizePin())
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
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.tabBarMinimizeBehavior(.onScrollDown)
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

/// Full-screen cover for the app-switcher snapshot — the rice canvas
/// and the mascot, none of the numbers.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Color.riceCanvas.ignoresSafeArea()
            Text("🍙")
                .font(.system(size: 64))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
