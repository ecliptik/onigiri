import AppIntents
import WidgetKit
import OnigiriKit

/// One tap on the widget: log a standard serving of water to Apple Health.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Logs one serving of water to Apple Health.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await HealthKitService().logWater(oz: SharedStore.waterServingOz)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// One tap on the widget: log a saved meal to Apple Health.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription("Logs a saved meal to Apple Health.")

    @Parameter(title: "Meal") var meal: MealEntity

    init() {}
    init(meal: MealEntity) {
        self.meal = meal
    }

    @MainActor
    func perform() async throws -> some IntentResult {
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
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private enum LogIntentError: LocalizedError {
    case mealMissing(String)

    var errorDescription: String? {
        switch self {
        case .mealMissing(let name):
            "“\(name)” is no longer a saved meal — edit the widget to pick another."
        }
    }
}

/// Widget configuration: which saved meal the quick-log button targets.
struct MeterWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Onigiri"
    static let description = IntentDescription("Choose the meal for the quick-log button.")

    @Parameter(title: "Meal") var meal: MealEntity?
}
