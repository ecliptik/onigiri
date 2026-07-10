import Foundation

/// A meal as it travels from iPhone to Watch: just what one-tap logging needs.
public struct SyncedMeal: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let kcal: Double
    public let sodiumMg: Double

    public init(id: UUID, name: String, kcal: Double, sodiumMg: Double) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
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

/// Everything one WatchConnectivity application context carries.
public struct SyncPayload: Sendable {
    public let meals: [SyncedMeal]
    public let goal: SyncedGoal?
    public let waterServingOz: Double?
    public let waterGoalOz: Double?
    public let balanceStyle: String?

    public init(
        meals: [SyncedMeal],
        goal: SyncedGoal?,
        waterServingOz: Double?,
        waterGoalOz: Double?,
        balanceStyle: String? = nil
    ) {
        self.meals = meals
        self.goal = goal
        self.waterServingOz = waterServingOz
        self.waterGoalOz = waterGoalOz
        self.balanceStyle = balanceStyle
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
        balanceStyle: String = "balance"
    ) -> [String: Any] {
        var context: [String: Any] = [
            SharedStore.waterServingKey: waterServingOz,
            SharedStore.waterGoalKey: waterGoalOz,
            SharedStore.balanceStyleKey: balanceStyle,
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
        var meals: [SyncedMeal] = []
        if let data = context[mealsKey] as? Data,
           let decoded = try? JSONDecoder().decode([SyncedMeal].self, from: data) {
            meals = decoded
        }
        var goal: SyncedGoal?
        if let data = context[goalKey] as? Data {
            goal = try? JSONDecoder().decode(SyncedGoal.self, from: data)
        }
        return SyncPayload(
            meals: meals,
            goal: goal,
            waterServingOz: context[SharedStore.waterServingKey] as? Double,
            waterGoalOz: context[SharedStore.waterGoalKey] as? Double,
            balanceStyle: context[SharedStore.balanceStyleKey] as? String
        )
    }

    public static func store(_ payload: SyncPayload) {
        let defaults = SharedStore.defaults
        if let data = try? JSONEncoder().encode(payload.meals) {
            defaults.set(data, forKey: mealsKey)
        }
        if let goal = payload.goal, let data = try? JSONEncoder().encode(goal) {
            defaults.set(data, forKey: goalKey)
        } else if payload.goal == nil {
            defaults.removeObject(forKey: goalKey)
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
