import SwiftUI
import SwiftData
import OnigiriKit

@main
struct OnigiriApp: App {
    /// Shared App Group container so the widget extension sees the library.
    private static let container: ModelContainer = {
        do {
            return try SharedStore.modelContainer()
        } catch {
            fatalError("Could not open the shared data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.container)
    }
}
