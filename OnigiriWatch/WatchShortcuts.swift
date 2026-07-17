import AppIntents
import OnigiriKit

// The intents compile into this target from SharedIntents/ (linkd
// rejects SPM-package App Shortcuts — see LogWaterIntent.swift).

/// The phone's Siri surface, minus describe-to-log (no Foundation
/// Models on watchOS). Same phrases — muscle memory shouldn't care
/// which device heard you.
struct OnigiriWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)",
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log \(\.$meal) in \(.applicationName)",
                "Log a meal in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Log a food in \(.applicationName)",
            ],
            shortTitle: "Log Food",
            systemImageName: "carrot"
        )
        AppShortcut(
            intent: CheckTodayIntent(metric: .caloriesLeft),
            phrases: [
                "How many calories do I have left in \(.applicationName)",
                "Check my calories in \(.applicationName)",
            ],
            shortTitle: "Calories Left",
            systemImageName: "gauge.with.needle"
        )
        AppShortcut(
            intent: CheckTodayIntent(metric: .water),
            phrases: [
                "How much water have I had in \(.applicationName)",
                "Check my water in \(.applicationName)",
            ],
            shortTitle: "Water Today",
            systemImageName: "drop"
        )
    }

    /// Nori green, like the icon (and the phone's tiles).
    static let shortcutTileColor: ShortcutTileColor = .lime
}
