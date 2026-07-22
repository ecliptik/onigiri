// SharedIntents/ files compile INTO each target (app, widget extension,
// watch app) rather than living in OnigiriKit: linkd refuses App
// Shortcuts whose intents arrive via an SPM package — the device log
// says "aggregateMetadataIsEmpty" and the app never registers with
// Siri/Shortcuts (FB13281659; cost a full evening on 2026-07-16). The
// per-target copy is the layout that worked before 2.1 moved these
// into the kit and silently broke registration.
import AppIntents
import OnigiriKit

/// One tap: log a standard serving of water to Apple Health — or, from
/// Shortcuts/Siri, a specific number of ounces ("at 10 PM log 20 oz").
/// The parameter is optional so every existing surface (widget button,
/// Control Center, the plain Siri phrase) still one-shots the default
/// serving with no questions asked.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Logs a serving of water to Apple Health.")

    @Parameter(title: "Ounces") var ounces: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Log Water") {
            \.$ounces
        }
    }

    init() {}
    init(ounces: Double?) {
        self.ounces = ounces
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Clamp typed/spoken amounts to sanity — 0/negative fall back to
        // the serving, and nobody drinks a gallon in one log.
        let oz = ounces.flatMap { $0 > 0 ? min($0, 128) : nil } ?? SharedStore.waterServingOz
        try await HealthKitService().logWater(oz: oz)
        // Immediate and scoped: the intent process may die before a
        // debounced flush, and a water log can't move the weight trend
        // or streak widgets.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.waterAccessory, WidgetKinds.todayCard,
        ])
        // The parameter stays ounces (a display-unit parameter would make
        // "log 20" ambiguous across installs); only the reply converts.
        let unit = SharedStore.waterUnit
        let shown = unit.fromOz(oz)
        return .result(dialog: IntentDialog(
            stringLiteral: "Logged \(shown.formatted(.number.precision(.fractionLength(0)))) \(unit.spoken(shown)) of water."))
    }
}
