import AppIntents
import SwiftUI
import WidgetKit
import OnigiriKit

// LogWaterIntent compiles into this target from SharedIntents/ (linkd
// rejects SPM-package App Shortcuts metadata — the extension gets its
// own copy, exactly the pre-2.1 layout that worked).

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
