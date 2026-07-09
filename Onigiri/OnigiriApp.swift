import SwiftUI
import SwiftData

@main
struct OnigiriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self])
    }
}
