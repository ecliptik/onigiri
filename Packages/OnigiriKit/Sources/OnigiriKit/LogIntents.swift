#if canImport(HealthKit) && canImport(WidgetKit)
import AppIntents
import os

// Logger is thread-safe; opt out of any MainActor default.
private nonisolated(unsafe) let configLog = Logger(subsystem: "com.ecliptik.Onigiri.widgets", category: "config")

/// The intents live in the KIT so one definition serves the widget
/// buttons, the Control Center control, and Siri/Spotlight App
/// Shortcuts — app and extensions register this package via
/// `AppIntentsPackage.includedPackages`.
public struct OnigiriKitIntents: AppIntentsPackage {
    public init() {}
}

/// One tap: log a standard serving of water to Apple Health.
public struct LogWaterIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Water"
    public static let description = IntentDescription("Logs one serving of water to Apple Health.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try await HealthKitService().logWater(oz: SharedStore.waterServingOz)
        // Immediate and scoped: the intent process may die before a
        // debounced flush, and a water log can't move the weight trend
        // or streak widgets.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.waterAccessory, WidgetKinds.todayCard,
        ])
        return .result()
    }
}

/// One tap: log a saved meal to Apple Health.
public struct LogMealIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Meal"
    public static let description = IntentDescription("Logs a saved meal to Apple Health.")

    @Parameter(title: "Meal") public var meal: MealEntity

    /// Required for Spotlight/quick-run surfaces (a required parameter
    /// with no default hides the intent without one) and gives Shortcuts
    /// the natural "Log Chicken & rice" phrasing.
    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal)")
    }

    public init() {}
    public init(meal: MealEntity) {
        self.meal = meal
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        // Meals re-created on the phone get new UUIDs; fall back to the
        // name so a stale widget configuration keeps working. A true
        // miss must throw — returning .result() reads as success and
        // the widget button becomes a permanent silent no-op.
        let meals = WatchSync.loadMeals()
        guard let match = meals.first(where: { $0.id.uuidString == meal.id })
            ?? meals.first(where: { $0.name == meal.name }) else {
            throw LogIntentError.mealMissing(meal.name)
        }
        try await HealthKitService().logFood(
            name: match.name,
            kcal: match.kcal,
            sodiumMg: match.sodiumMg,
            nutrients: match.nutrients ?? NutrientValues(),
            category: match.category.flatMap(FoodCategory.init(rawValue:))
        )
        // Immediate and scoped (see LogWaterIntent) — a meal touches every
        // energy surface but not water or the weight trend.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.gauge, WidgetKinds.streak, WidgetKinds.monthStats,
            WidgetKinds.todayCard,
        ])
        return .result()
    }
}

// PageTodayCardIntent + TodayCardBrowse removed 2.1: the ‹ › day paging
// they backed wouldn't dispatch as a WidgetKit AppIntent button on the
// device, so the Today card dropped paging for the reliable Log deep
// link. LogWaterIntent stays — the Control Center control and Siri use
// it.

private enum LogIntentError: LocalizedError {
    case mealMissing(String)

    var errorDescription: String? {
        switch self {
        case .mealMissing(let name):
            "“\(name)” is no longer a saved meal — edit the widget to pick another."
        }
    }
}

/// A saved meal, exposed to widget configuration ("Edit Widget" → pick
/// meal) and the meal intent. Reads the lightweight mirror in the App
/// Group defaults — widget processes are memory-capped, so no SwiftData.
public struct MealEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Meal"
    public static let defaultQuery = MealEntityQuery()

    public var id: String
    public var name: String
    public var kcal: Double

    public init(id: String, name: String, kcal: Double) {
        self.id = id
        self.name = name
        self.kcal = kcal
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kcal.formatted(.number.precision(.fractionLength(0)))) kcal"
        )
    }
}

public struct MealEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [MealEntity] {
        let meals = allMeals()
        configLog.info("entities(for: \(identifiers.count)) -> \(meals.count) meals in mirror")
        return meals.filter { identifiers.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [MealEntity] {
        let meals = allMeals()
        configLog.info("suggestedEntities -> \(meals.count) meals in mirror")
        return meals
    }

    private func allMeals() -> [MealEntity] {
        WatchSync.loadMeals().map {
            MealEntity(id: $0.id.uuidString, name: $0.name, kcal: $0.kcal)
        }
    }
}
#endif
