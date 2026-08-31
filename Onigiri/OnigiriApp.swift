import SwiftUI
import SwiftData
import UIKit
import OnigiriKit

@main
struct OnigiriApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Shared App Group container so the widget extension sees the library.
    private static let container: ModelContainer = {
        do {
            return try SharedStore.modelContainer()
        } catch {
            fatalError("Could not open the shared data store: \(error)")
        }
    }()

    /// Holds the HKObserverQuery alive for the app's lifetime — a log
    /// arriving from the watch (or any app) refreshes the widgets.
    /// Registered HERE, not in a view: background delivery can relaunch
    /// the app without ever running scene content's .task.
    @State private var logObserver: HealthKitService

    init() {
        // Heal stores poisoned before Food↔MealItem had an inverse: a meal
        // item pointing at a deleted food crashed every launch as soon as
        // anything computed meal totals (e.g. the watch sync push). The
        // Core Data pass must run before SwiftData opens the store —
        // SwiftData traps on the dangling reference it needs to inspect.
        // Deliberately NOT one-shot: repairStore can be skipped or fail
        // silently, and a "repaired" flag that outlives the store file it
        // judged would gate off the only recovery from a crash loop. The
        // per-launch cost (a small scan of a personal library) is the
        // cheaper side of that trade.
        //
        // GATED on repairStore's own result (health-check audit,
        // 2026-08-31): repairDanglingFoodReferences touches every
        // MealItem.food unconditionally, and SwiftData kills the process
        // the instant that resolves a genuinely dangling reference. A
        // Void-returning repairStore let a silent failure here (bad
        // bridge, locked file, failed save) run straight into that touch
        // on EVERY subsequent launch — turning a one-time repair failure
        // into a permanent crash loop, the exact class this mechanism
        // exists to prevent. No store to check (fresh install) counts as
        // safe, same as repairStore's own "nothing to repair" exit.
        let safeToProceed = SharedStore.storeURL.map { LibraryMaintenance.repairStore(at: $0) } ?? true
        if safeToProceed {
            LibraryMaintenance.repairDanglingFoodReferences(context: Self.container.mainContext)
        }

        let observer = HealthKitService()
        observer.startObservingLogChanges {
            // Debounced funnel: one meal writes a burst of samples (and
            // the observer covers watch/third-party logs too) — coalesce
            // them into a single kind-scoped reload. Runs before the
            // observer completes, so a background wake can't suspend
            // out from under it.
            await MainActor.run {
                ToastCenter.shared.noteHealthWrite()
                WidgetReloader.requestReload(kinds: WidgetKinds.phoneLogAffected)
                // Stamp the log and push the context: the stamp's change
                // is what wakes the watch and reloads its complications —
                // HealthKit syncs the sample itself, but its watchOS
                // background delivery is hourly at best, and the watch
                // deliberately ignores library-only context churn.
                WatchSync.stampPhoneLog()
                PhoneSyncService.shared.push(from: Self.container.mainContext)
                // A background wake suspends after completion — flush the
                // debounces before the window closes.
                if UIApplication.shared.applicationState != .active {
                    WidgetReloader.flushNow()
                    PhoneSyncService.shared.flushNow()
                }
            }
            // Reminders bake their numbers in at planning time, so a log
            // arriving from OUTSIDE the app UI (watch, widget button,
            // Control Center, Siri, another Health app) must replan or
            // the pre-scheduled bodies go stale — the 11 AM water
            // check-in read "0 of 72 oz" after a morning of watch-logged
            // water (2026-07-16). AWAITED, not fired-and-forgotten: the
            // wake suspends after the observer completes, and a detached
            // replan would be stranded mid-flight.
            await ReminderScheduler.shared.replanNow(afterMutation: true)
        }
        // Today's ACTIVE energy — the only input that moves the day's
        // budget between midnight and bedtime, and until 2026-08-03 the
        // only one nothing observed. A walk raised the budget in the app
        // (which re-queries every foreground) while the home-screen
        // widget held its morning number until the app was opened.
        //
        // Fires often; reloads rarely. `refreshIfBurnMoved` runs the
        // shared gate — ≥40 kcal moved AND ≥10 min since the last
        // burn reload — so the ~40–70/day reload budget is spent only on
        // changes that alter what's on screen. Scoped to the
        // budget-shaped widgets: water, streak and month can't move on
        // burn (the streak/month surfaces judge COMPLETED days).
        observer.startObservingBurnChanges {
            let reloaded = await BurnWidgetRefresh.refreshIfBurnMoved(
                kinds: WidgetKinds.phoneBurnAffected
            )
            // A background wake suspends the moment the observer
            // completes — a debounced reload left sleeping would die
            // with it, exactly as the log observer guards against.
            if reloaded {
                await MainActor.run {
                    if UIApplication.shared.applicationState != .active {
                        WidgetReloader.flushNow()
                    }
                }
            }
        }
        // Weigh-ins from anywhere else (Health app, smart scale, another
        // tracker). Its own observer and its own version, because the
        // Goal tab is the only screen that reads body mass and the
        // food/water surfaces must not re-query for a weigh-in. No
        // widget reload or reminder replan here either: nothing else
        // reads weight (the trend widget polls itself).
        observer.startObservingWeightChanges {
            await MainActor.run {
                ToastCenter.shared.noteWeightWrite()
            }
        }
        _logObserver = State(initialValue: observer)
    }

    /// @AppStorage, not a static read: the Theme picker must repaint the
    /// whole app the moment it changes (the Appearance-picker precedent).
    @AppStorage(SharedStore.appearanceKey, store: SharedStore.defaults)
    private var appearance = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                // nil for System — see AppTheme for what this does NOT
                // cover (widgets, the watch, the launch screen).
                .preferredColorScheme(AppTheme.resolve(appearance).colorScheme)
                // …and the window-level override, which is what actually
                // carries the theme into SHEETS (the picker's own screen
                // is one). preferredColorScheme alone left Settings on the
                // old appearance — see AppearanceWindow.
                .onAppear { AppearanceWindow.apply() }
                .onChange(of: appearance) { _, raw in
                    AppearanceWindow.apply(AppTheme.resolve(raw))
                }
        }
        .modelContainer(Self.container)
    }
}
