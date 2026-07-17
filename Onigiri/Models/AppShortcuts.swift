import AppIntents
import OnigiriKit

// The intents themselves compile into this target from SharedIntents/
// (linkd rejects SPM-package App Shortcuts — see LogWaterIntent.swift).

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
        // Ask-back queries (PLAN-siri 2.5): preset-metric shortcuts so
        // the natural question completes in one exchange — no
        // clarification step.
        AppShortcut(
            intent: CheckTodayIntent(metric: .caloriesLeft),
            phrases: [
                "How many calories do I have left in \(.applicationName)",
                "How many calories are left in \(.applicationName)",
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
        AppShortcut(
            intent: CheckTodayIntent(metric: .sodium),
            phrases: [
                "How much sodium have I had in \(.applicationName)",
                "Check my sodium in \(.applicationName)",
            ],
            shortTitle: "Sodium Today",
            systemImageName: "aqi.medium"
        )
        // Every macro askable by name — "How much protein have I had in
        // Onigiri?" — with the enum substituting each case into the
        // phrase. Slot-tracked nutrients answer against their target.
        AppShortcut(
            intent: CheckTodayIntent(),
            phrases: [
                "How much \(\.$metric) have I had in \(.applicationName)",
                "Check my \(\.$metric) in \(.applicationName)",
                "How much \(\.$metric) today in \(.applicationName)",
            ],
            shortTitle: "Check Today",
            systemImageName: "chart.bar.xaxis"
        )
        // Describe-to-log: AppShortcutsBuilder only accepts #available
        // conditions (runtime gates like FoodIntelligence.isAvailable
        // don't compile), so the phrase exists on every iOS 26 device
        // and the INTENT carries the gate — on a non-AI device it fails
        // with the friendly "needs Apple Intelligence" error instead of
        // hiding. (The freeform description can't ride IN the phrase;
        // Siri asks "What did you eat?" — one extra exchange.)
        if #available(iOS 26.0, *) {
            AppShortcut(
                intent: DescribeFoodIntent(),
                phrases: [
                    "Describe a food in \(.applicationName)",
                    "Describe what I ate in \(.applicationName)",
                ],
                shortTitle: "Describe & Log",
                systemImageName: "sparkles"
            )
        }
    }

    /// Nori green, like the icon.
    static let shortcutTileColor: ShortcutTileColor = .lime
}
