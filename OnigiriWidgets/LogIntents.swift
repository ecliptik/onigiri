import AppIntents
import SwiftData
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
        let container = try SharedStore.modelContainer()
        let meals = try container.mainContext.fetch(FetchDescriptor<Meal>())
        guard let match = meals.first(where: { $0.uuid.uuidString == meal.id }) else {
            return .result()
        }
        try await HealthKitService().logFood(
            name: match.name,
            kcal: match.totalKcal,
            sodiumMg: match.totalSodiumMg
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Widget configuration: which saved meal the quick-log button targets.
struct MeterWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Onigiri"
    static let description = IntentDescription("Choose the meal for the quick-log button.")

    @Parameter(title: "Meal button") var meal: MealEntity?
}
