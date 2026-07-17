// Compiled into the app and watch targets directly — see
// LogWaterIntent.swift for why these must not live in the kit (linkd
// rejects SPM-delivered App Shortcuts metadata).
import AppIntents
import Foundation
import OnigiriKit
import os

// Logger is thread-safe; opt out of any MainActor default.
private nonisolated(unsafe) let intentLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "intents")

/// One tap or one Siri phrase: log a saved meal to Apple Health.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription("Logs a saved meal to Apple Health.")

    @Parameter(title: "Meal") var meal: MealEntity

    /// Required for Spotlight/quick-run surfaces (a required parameter
    /// with no default hides the intent without one) and gives Shortcuts
    /// the natural "Log Chicken & rice" phrasing.
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal)")
    }

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
        // Immediate and scoped (see LogWaterIntent) — a meal touches every
        // energy surface but not water or the weight trend.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.gauge, WidgetKinds.streak, WidgetKinds.monthStats,
            WidgetKinds.todayCard,
        ])
        return .result()
    }
}

/// One tap or one Siri phrase: log a food from the favorites/recents
/// mirror to Apple Health. Same shape as LogMealIntent — everything in
/// the mirror is SyncedMeal-shaped with combined totals.
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Logs a favorite or recent food to Apple Health.")

    @Parameter(title: "Food") var food: FoodEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$food)")
    }

    init() {}
    init(food: FoodEntity) {
        self.food = food
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // ID first, name fallback — recency churn re-creates entries
        // (see LogMealIntent); a true miss throws so Siri says why.
        let foods = FoodEntityQuery.loggableFoods()
        guard let match = foods.first(where: { $0.id.uuidString == food.id })
            ?? foods.first(where: { $0.name == food.name }) else {
            throw LogIntentError.foodMissing(food.name)
        }
        try await HealthKitService().logFood(
            name: match.name,
            kcal: match.kcal,
            sodiumMg: match.sodiumMg,
            nutrients: match.nutrients ?? NutrientValues(),
            category: match.category.flatMap(FoodCategory.init(rawValue:))
        )
        // Same scope as a meal: every energy surface, not water/trend.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.gauge, WidgetKinds.streak, WidgetKinds.monthStats,
            WidgetKinds.todayCard,
        ])
        return .result()
    }
}

private enum LogIntentError: LocalizedError {
    case mealMissing(String)
    case foodMissing(String)

    var errorDescription: String? {
        switch self {
        case .mealMissing(let name):
            "“\(name)” is no longer a saved meal — edit the widget to pick another."
        case .foodMissing(let name):
            "“\(name)” isn’t in your favorites or recent foods anymore."
        }
    }
}

/// A saved meal, exposed to the meal intent and Siri. Reads the
/// lightweight mirror in the App Group defaults — intent processes are
/// memory-capped, so no SwiftData.
struct MealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Meal"
    static let defaultQuery = MealEntityQuery()

    var id: String
    var name: String
    var kcal: Double

    init(id: String, name: String, kcal: Double) {
        self.id = id
        self.name = name
        self.kcal = kcal
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kcal.formatted(.number.precision(.fractionLength(0)))) kcal"
        )
    }
}

struct MealEntityQuery: EntityQuery, EntityStringQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [MealEntity] {
        let meals = allMeals()
        intentLog.info("entities(for: \(identifiers.count)) -> \(meals.count) meals in mirror")
        return meals.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MealEntity] {
        let meals = allMeals()
        intentLog.info("suggestedEntities -> \(meals.count) meals in mirror")
        return meals
    }

    /// Siri resolution for spoken names ("log chicken and rice"):
    /// case-insensitive containment beats exact match on speech.
    func entities(matching string: String) async throws -> [MealEntity] {
        allMeals().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    private func allMeals() -> [MealEntity] {
        WatchSync.loadMeals().map {
            MealEntity(id: $0.id.uuidString, name: $0.name, kcal: $0.kcal)
        }
    }
}

/// A loggable food for Siri/Shortcuts: the favorites + recents mirror,
/// minus anything that's a saved meal (those belong to LogMealIntent —
/// keeping the vocabularies disjoint keeps Siri's matching clean).
struct FoodEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Food"
    static let defaultQuery = FoodEntityQuery()

    var id: String
    var name: String
    var kcal: Double

    init(id: String, name: String, kcal: Double) {
        self.id = id
        self.name = name
        self.kcal = kcal
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kcal.formatted(.number.precision(.fractionLength(0)))) kcal"
        )
    }
}

struct FoodEntityQuery: EntityQuery, EntityStringQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [FoodEntity] {
        allFoods().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FoodEntity] {
        allFoods()
    }

    func entities(matching string: String) async throws -> [FoodEntity] {
        allFoods().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    /// The mirror slices Siri can log from, deduped (favorites and
    /// recents overlap), meals excluded.
    static func loggableFoods() -> [SyncedMeal] {
        let mealIDs = Set(WatchSync.loadMeals().map(\.id))
        var seen = Set<UUID>()
        return (WatchSync.loadFavorites() + WatchSync.loadRecentFoods())
            .filter { !mealIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    private func allFoods() -> [FoodEntity] {
        Self.loggableFoods().map {
            FoodEntity(id: $0.id.uuidString, name: $0.name, kcal: $0.kcal)
        }
    }
}
