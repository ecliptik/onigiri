import AppIntents
import SwiftUI
import WidgetKit
import OnigiriKit

/// The log intents live in OnigiriKit (one definition for widget
/// buttons, Control Center, and Siri) — this registers the kit's
/// intents package for the widget extension's process.
struct OnigiriWidgetsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OnigiriKitIntents.self]
    }
}

/// Control Center / Action button: one press logs a serving of water.
struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OnigiriLogWaterControl") {
            ControlWidgetButton(action: LogWaterIntent()) {
                Label("Log Water", systemImage: "drop.fill")
            }
        }
        .displayName("Log Water")
        .description("Logs one serving of water to Apple Health.")
    }
}
