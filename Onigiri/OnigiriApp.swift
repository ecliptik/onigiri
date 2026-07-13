import SwiftUI
import SwiftData
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.container)
    }
}
