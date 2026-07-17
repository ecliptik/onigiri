import AppIntents
import OnigiriKit

/// The log intents live in OnigiriKit — register the kit's intents
/// package for the app's process (the widget extension registers it
/// separately for its own).
struct OnigiriAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OnigiriKitIntents.self]
    }
}

/// Zero-setup Siri/Spotlight phrases over the existing intents. The
/// parameterized phrases speak library names ("Log chicken and rice in
/// Onigiri") — their vocabulary comes from the entity queries'
/// suggestedEntities, refreshed via updateAppShortcutParameters()
/// whenever PhoneSyncService rewrites the mirror.
struct OnigiriShortcuts: AppShortcutsProvider {
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
    }

    /// Nori green, like the icon.
    static let shortcutTileColor: ShortcutTileColor = .lime
}
