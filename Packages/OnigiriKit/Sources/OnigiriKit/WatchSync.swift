import Foundation

/// A meal as it travels from iPhone to Watch: what one-tap logging needs.
/// Category and nutrients are optional so payloads from older phones still
/// decode — without them a watch/widget log falls back to time-of-day slot
/// inference and kcal+sodium only.
public struct SyncedMeal: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let kcal: Double
    public let sodiumMg: Double
    public let category: String?
    public let nutrients: NutrientValues?

    public init(
        id: UUID, name: String, kcal: Double, sodiumMg: Double,
        category: String? = nil, nutrients: NutrientValues? = nil
    ) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.category = category
        self.nutrients = nutrients
    }
}

/// The weight goal as it travels to the watch; the watch combines it with
/// its own HealthKit weight/burn data to compute the daily plan.
public struct SyncedGoal: Codable, Sendable, Equatable {
    public let targetWeightLb: Double
    public let targetDate: Date
    public let fallbackCurrentWeightLb: Double?

    public init(targetWeightLb: Double, targetDate: Date, fallbackCurrentWeightLb: Double?) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
    }
}

/// What a sync says to do with the watch's stored goal. "Absent from the
/// context" means the phone has no goal (clear it); "present but
/// undecodable" (version skew) must keep the last good copy, not wipe it.
public enum GoalUpdate: Sendable, Equatable {
    case set(SyncedGoal)
    case clear
    case keep
}

/// Everything one WatchConnectivity application context carries.
public struct SyncPayload: Sendable {
    /// nil when the meals data was missing or failed to decode — keep the
    /// watch's last good list.
    public let meals: [SyncedMeal]?
    public let goal: GoalUpdate
    public let waterServingOz: Double?
    public let waterGoalOz: Double?
    public let balanceStyle: String?
    /// Icon personalization rides along so the watch matches the phone.
    public let foodIcon: String?
    public let waterIcon: String?

    public init(
        meals: [SyncedMeal]?,
        goal: GoalUpdate,
        waterServingOz: Double?,
        waterGoalOz: Double?,
        balanceStyle: String? = nil,
        foodIcon: String? = nil,
        waterIcon: String? = nil
    ) {
        self.meals = meals
        self.goal = goal
        self.waterServingOz = waterServingOz
        self.waterGoalOz = waterGoalOz
        self.balanceStyle = balanceStyle
        self.foodIcon = foodIcon
        self.waterIcon = waterIcon
    }
}

/// Encoding/decoding of the phone→watch application context, and watch-side
/// persistence into the shared defaults (readable by complications).
public enum WatchSync {
    static let mealsKey = "sync.meals"
    static let goalKey = "sync.goal"

    // MARK: Phone side

    public static func makeContext(
        meals: [SyncedMeal],
        goal: SyncedGoal?,
        waterServingOz: Double,
        waterGoalOz: Double,
        balanceStyle: String = "balance",
        foodIcon: String = "sfFork",
        waterIcon: String = "sfDrop"
    ) -> [String: Any] {
        var context: [String: Any] = [
            SharedStore.waterServingKey: waterServingOz,
            SharedStore.waterGoalKey: waterGoalOz,
            SharedStore.balanceStyleKey: balanceStyle,
            SharedStore.foodIconKey: foodIcon,
            SharedStore.waterIconKey: waterIcon,
        ]
        if let data = try? JSONEncoder().encode(meals) {
            context[mealsKey] = data
        }
        if let goal, let data = try? JSONEncoder().encode(goal) {
            context[goalKey] = data
        }
        return context
    }

    // MARK: Watch side

    public static func parse(_ context: [String: Any]) -> SyncPayload {
        let meals: [SyncedMeal]? = (context[mealsKey] as? Data)
            .flatMap { try? JSONDecoder().decode([SyncedMeal].self, from: $0) }
        let goal: GoalUpdate
        if let data = context[goalKey] as? Data {
            goal = (try? JSONDecoder().decode(SyncedGoal.self, from: data))
                .map(GoalUpdate.set) ?? .keep
        } else {
            goal = .clear
        }
        return SyncPayload(
            meals: meals,
            goal: goal,
            waterServingOz: context[SharedStore.waterServingKey] as? Double,
            waterGoalOz: context[SharedStore.waterGoalKey] as? Double,
            balanceStyle: context[SharedStore.balanceStyleKey] as? String,
            foodIcon: context[SharedStore.foodIconKey] as? String,
            waterIcon: context[SharedStore.waterIconKey] as? String
        )
    }

    public static func store(_ payload: SyncPayload) {
        let defaults = SharedStore.defaults
        if let meals = payload.meals, let data = try? JSONEncoder().encode(meals) {
            defaults.set(data, forKey: mealsKey)
        }
        switch payload.goal {
        case .set(let goal):
            if let data = try? JSONEncoder().encode(goal) {
                defaults.set(data, forKey: goalKey)
            }
        case .clear:
            defaults.removeObject(forKey: goalKey)
        case .keep:
            break
        }
        if let serving = payload.waterServingOz {
            defaults.set(serving, forKey: SharedStore.waterServingKey)
        }
        if let goalOz = payload.waterGoalOz {
            defaults.set(goalOz, forKey: SharedStore.waterGoalKey)
        }
        if let style = payload.balanceStyle {
            defaults.set(style, forKey: SharedStore.balanceStyleKey)
        }
        if let foodIcon = payload.foodIcon {
            defaults.set(foodIcon, forKey: SharedStore.foodIconKey)
        }
        if let waterIcon = payload.waterIcon {
            defaults.set(waterIcon, forKey: SharedStore.waterIconKey)
        }
    }

    public static func loadMeals() -> [SyncedMeal] {
        guard let data = SharedStore.defaults.data(forKey: mealsKey) else { return [] }
        return (try? JSONDecoder().decode([SyncedMeal].self, from: data)) ?? []
    }

    public static func loadGoal() -> SyncedGoal? {
        guard let data = SharedStore.defaults.data(forKey: goalKey) else { return nil }
        return try? JSONDecoder().decode(SyncedGoal.self, from: data)
    }
}
