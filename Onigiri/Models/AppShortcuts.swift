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

/// Zero-setup Siri/Spotlight phrases over the existing intents.
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
    }
}
