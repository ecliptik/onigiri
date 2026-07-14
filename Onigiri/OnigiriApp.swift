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
        if let url = SharedStore.storeURL {
            LibraryMaintenance.repairStore(at: url)
        }
        LibraryMaintenance.repairDanglingFoodReferences(context: Self.container.mainContext)

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
                // A background wake suspends after completion — flush the
                // debounce before the window closes.
                if UIApplication.shared.applicationState != .active {
                    WidgetReloader.flushNow()
                }
            }
        }
        _logObserver = State(initialValue: observer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.container)
    }
}
