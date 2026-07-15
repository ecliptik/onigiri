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
        configLog.info("LogWaterIntent.perform starting")
        try await HealthKitService().logWater(oz: SharedStore.waterServingOz)
        // Immediate and scoped: the intent process may die before a
        // debounced flush, and a water log can't move the weight trend
        // or streak widgets.
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.waterAccessory, WidgetKinds.todayCard,
        ])
        configLog.info("LogWaterIntent.perform done")
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
            WidgetKinds.gauge, WidgetKinds.streak, WidgetKinds.todayCard,
        ])
        return .result()
    }
}

/// Browsed-day state for the Today card, in the App Group defaults.
/// The snap-back rule (the user): a browsed day is only honored while
/// its anchor — the "today" it was browsed FROM — is still today; at day
/// roll the card renders the new today, nobody wakes up to Tuesday's
/// numbers. Lives in the kit so PageTodayCardIntent (registered into the
/// widget process via OnigiriKitIntents) can reach it.
public enum TodayCardBrowse {
    static let dayKey = "todayCard.browsedDay"
    static let anchorKey = "todayCard.browsedAnchor"
    /// Paging floor: the kit's 92-day totals window (today + 91 back).
    public static let daysBack = 91

    /// The day the card should show; nil means today.
    public static func shownDay(now: Date = .now) -> Date? {
        let defaults = SharedStore.defaults
        guard let stored = defaults.object(forKey: dayKey) as? Date,
              let anchor = defaults.object(forKey: anchorKey) as? Date else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        guard Calendar.current.isDate(anchor, inSameDayAs: today), stored < today else {
            clear()
            return nil
        }
        return stored
    }

    public static func page(by delta: Int, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let shown = shownDay(now: now) ?? today
        guard let target = calendar.date(byAdding: .day, value: delta, to: shown),
              let floor = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return }
        let clamped = min(max(target, floor), today)
        if clamped == today {
            clear()
        } else {
            SharedStore.defaults.set(clamped, forKey: dayKey)
            SharedStore.defaults.set(today, forKey: anchorKey)
        }
    }

    public static func clear() {
        SharedStore.defaults.removeObject(forKey: dayKey)
        SharedStore.defaults.removeObject(forKey: anchorKey)
    }
}

/// ‹ › on the Today card. The system reloads the tapped widget's
/// timeline after perform, so writing the browsed day is the whole job.
public struct PageTodayCardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Browse Day on Today Widget"
    public static let description = IntentDescription("Shows another day on the Today widget.")
    // NOT isDiscoverable = false: a non-discoverable intent is absent
    // from the app-side metadata the interactive-widget action runner
    // queries at tap time ("no metadata for PageTodayCardIntent in the
    // app"), so the ‹ › buttons silently no-op. It rides in Shortcuts as
    // the cost of working paging — harmless without the widget in front
    // of you, and the title says where it belongs.

    @Parameter(title: "Days") public var delta: Int

    public init() {}
    public init(delta: Int) {
        self.delta = delta
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        configLog.info("PageTodayCardIntent.perform delta=\(delta)")
        TodayCardBrowse.page(by: delta)
        // The extension may die before a debounced flush; reload now.
        WidgetReloader.reloadNow(kinds: [WidgetKinds.todayCard])
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
