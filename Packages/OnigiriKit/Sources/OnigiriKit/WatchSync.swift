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
public struct SyncedGoal: Codable, Sendable, Equatable, Hashable {
    public let targetWeightLb: Double
    public let targetDate: Date
    public let fallbackCurrentWeightLb: Double?
    /// "lose" (nil, the historical default) or "maintain" — optional so
    /// payloads survive version skew in both directions.
    public let mode: String?

    public init(
        targetWeightLb: Double, targetDate: Date,
        fallbackCurrentWeightLb: Double?, mode: String? = nil
    ) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
        self.mode = mode
    }

    public var isMaintenance: Bool { mode == GoalMode.maintain }
}

/// The two goal modes, as stored strings (SwiftData + sync payload).
public enum GoalMode {
    public static let lose = "lose"
    public static let maintain = "maintain"
}

/// What a sync says to do with the watch's stored goal. "Absent from the
/// context" means the phone has no goal (clear it); "present but
/// undecodable" (version skew) must keep the last good copy, not wipe it.
public enum GoalUpdate: Sendable, Equatable, Hashable {
    case set(SyncedGoal)
    case clear
    case keep
}

/// Everything one WatchConnectivity application context carries.
/// Hashable so the phone's push can fingerprint the whole payload —
/// a hand-enumerated field list silently missed future additions.
public struct SyncPayload: Sendable, Hashable {
    /// nil when the meals data was missing or failed to decode — keep the
    /// watch's last good list.
    public let meals: [SyncedMeal]?
    /// The phone's most recently used foods, SyncedMeal-shaped so the
    /// watch logs them through the same one-tap path. nil = keep.
    public let recentFoods: [SyncedMeal]?
    /// Favorite foods and meals by recency — the watch's Favorites page
    /// mirrors the phone Log sheet's scope. nil = keep.
    public let favorites: [SyncedMeal]?
    public let goal: GoalUpdate
    public let waterServingOz: Double?
    public let waterGoalOz: Double?
    public let balanceStyle: String?
    /// Icon personalization rides along so the watch matches the phone.
    public let foodIcon: String?
    public let waterIcon: String?
    public let rewardIcon: String?
    /// The tracked-metric slots and the sodium limit their targets can
    /// reference — the watch's metrics page mirrors the phone's slots.
    /// Keyed by the SharedStore key, stored verbatim.
    public let trackedMetricSettings: [String: String]?
    public let sodiumLimitMg: Double?

    public init(
        meals: [SyncedMeal]?,
        recentFoods: [SyncedMeal]? = nil,
        favorites: [SyncedMeal]? = nil,
        goal: GoalUpdate,
        waterServingOz: Double?,
        waterGoalOz: Double?,
        balanceStyle: String? = nil,
        foodIcon: String? = nil,
        waterIcon: String? = nil,
        rewardIcon: String? = nil,
        trackedMetricSettings: [String: String]? = nil,
        sodiumLimitMg: Double? = nil
    ) {
        self.meals = meals
        self.recentFoods = recentFoods
        self.favorites = favorites
        self.goal = goal
        self.waterServingOz = waterServingOz
        self.waterGoalOz = waterGoalOz
        self.balanceStyle = balanceStyle
        self.foodIcon = foodIcon
        self.waterIcon = waterIcon
        self.rewardIcon = rewardIcon
        self.trackedMetricSettings = trackedMetricSettings
        self.sodiumLimitMg = sodiumLimitMg
    }
}

/// Encoding/decoding of the phone→watch application context, and watch-side
/// persistence into the shared defaults (readable by complications).
public enum WatchSync {
    static let mealsKey = "sync.meals"
    static let recentFoodsKey = "sync.recentFoods"
    static let favoritesKey = "sync.favorites"
    static let goalKey = "sync.goal"
    static let trackedKey = "sync.trackedMetrics"

    /// The one place the sync wire format is configured. Every encode and
    /// decode in this file must use these — SyncedGoal.targetDate crosses
    /// devices and app versions, so a single call site drifting to its own
    /// strategy would silently corrupt every round-trip (the decode paths
    /// are all `try?`). `.deferredToDate` is the historical default that
    /// deployed watches already have on disk and on the wire; changing it
    /// would orphan their stored goal, so it's pinned explicitly.
    /// Computed, not stored: JSONEncoder/JSONDecoder aren't Sendable.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// The slot settings that ride the context, values stringified
    /// (targets included — store() re-parses the numeric ones).
    public static var trackedMetricKeys: [String] { [
        SharedStore.trackedMetric1Key, SharedStore.trackedMetric1ModeKey,
        SharedStore.trackedMetric1TargetKey, SharedStore.trackedMetric1IconKey,
        SharedStore.trackedMetric2Key, SharedStore.trackedMetric2ModeKey,
        SharedStore.trackedMetric2TargetKey, SharedStore.trackedMetric2IconKey,
    ] }

    /// Numeric slot keys — stored back as Doubles on the watch. Public:
    /// the phone must send these even at 0 (reset-to-default), where
    /// string keys ride only when set.
    public static var trackedNumericKeys: Set<String> { [
        SharedStore.trackedMetric1TargetKey, SharedStore.trackedMetric2TargetKey,
    ] }

    // MARK: Phone side

    public static func makeContext(
        meals: [SyncedMeal],
        recentFoods: [SyncedMeal] = [],
        favorites: [SyncedMeal] = [],
        goal: SyncedGoal?,
        waterServingOz: Double,
        waterGoalOz: Double,
        balanceStyle: String = "balance",
        foodIcon: String = "sfFork",
        waterIcon: String = "sfDrop",
        rewardIcon: String = "onigiri",
        trackedMetricSettings: [String: String] = [:],
        sodiumLimitMg: Double = 2300
    ) -> [String: Any] {
        var context: [String: Any] = [
            SharedStore.waterServingKey: waterServingOz,
            SharedStore.waterGoalKey: waterGoalOz,
            SharedStore.balanceStyleKey: balanceStyle,
            SharedStore.foodIconKey: foodIcon,
            SharedStore.waterIconKey: waterIcon,
            SharedStore.rewardIconKey: rewardIcon,
            trackedKey: trackedMetricSettings,
            SharedStore.sodiumLimitKey: sodiumLimitMg,
        ]
        if let data = try? encoder.encode(meals) {
            context[mealsKey] = data
        }
        if let data = try? encoder.encode(recentFoods) {
            context[recentFoodsKey] = data
        }
        if let data = try? encoder.encode(favorites) {
            context[favoritesKey] = data
        }
        if let goal, let data = try? encoder.encode(goal) {
            context[goalKey] = data
        }
        return context
    }

    // MARK: Watch side

    public static func parse(_ context: [String: Any]) -> SyncPayload {
        let meals: [SyncedMeal]? = (context[mealsKey] as? Data)
            .flatMap { try? decoder.decode([SyncedMeal].self, from: $0) }
        let goal: GoalUpdate
        if let data = context[goalKey] as? Data {
            goal = (try? decoder.decode(SyncedGoal.self, from: data))
                .map(GoalUpdate.set) ?? .keep
        } else {
            goal = .clear
        }
        let recentFoods: [SyncedMeal]? = (context[recentFoodsKey] as? Data)
            .flatMap { try? decoder.decode([SyncedMeal].self, from: $0) }
        let favorites: [SyncedMeal]? = (context[favoritesKey] as? Data)
            .flatMap { try? decoder.decode([SyncedMeal].self, from: $0) }
        return SyncPayload(
            meals: meals,
            recentFoods: recentFoods,
            favorites: favorites,
            goal: goal,
            waterServingOz: context[SharedStore.waterServingKey] as? Double,
            waterGoalOz: context[SharedStore.waterGoalKey] as? Double,
            balanceStyle: context[SharedStore.balanceStyleKey] as? String,
            foodIcon: context[SharedStore.foodIconKey] as? String,
            waterIcon: context[SharedStore.waterIconKey] as? String,
            rewardIcon: context[SharedStore.rewardIconKey] as? String,
            trackedMetricSettings: context[trackedKey] as? [String: String],
            sodiumLimitMg: context[SharedStore.sodiumLimitKey] as? Double
        )
    }

    public static func store(_ payload: SyncPayload) {
        let defaults = SharedStore.defaults
        if let meals = payload.meals, let data = try? encoder.encode(meals) {
            defaults.set(data, forKey: mealsKey)
        }
        if let recents = payload.recentFoods, let data = try? encoder.encode(recents) {
            defaults.set(data, forKey: recentFoodsKey)
        }
        if let favorites = payload.favorites, let data = try? encoder.encode(favorites) {
            defaults.set(data, forKey: favoritesKey)
        }
        switch payload.goal {
        case .set(let goal):
            if let data = try? encoder.encode(goal) {
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
        if let rewardIcon = payload.rewardIcon {
            defaults.set(rewardIcon, forKey: SharedStore.rewardIconKey)
        }
        if let tracked = payload.trackedMetricSettings {
            for (key, value) in tracked {
                if trackedNumericKeys.contains(key) {
                    defaults.set(Double(value) ?? 0, forKey: key)
                } else {
                    defaults.set(value, forKey: key)
                }
            }
        }
        if let sodiumLimit = payload.sodiumLimitMg {
            defaults.set(sodiumLimit, forKey: SharedStore.sodiumLimitKey)
        }
    }

    public static func loadMeals() -> [SyncedMeal] {
        guard let data = SharedStore.defaults.data(forKey: mealsKey) else { return [] }
        return (try? decoder.decode([SyncedMeal].self, from: data)) ?? []
    }

    public static func loadRecentFoods() -> [SyncedMeal] {
        guard let data = SharedStore.defaults.data(forKey: recentFoodsKey) else { return [] }
        return (try? decoder.decode([SyncedMeal].self, from: data)) ?? []
    }

    public static func loadFavorites() -> [SyncedMeal] {
        guard let data = SharedStore.defaults.data(forKey: favoritesKey) else { return [] }
        return (try? decoder.decode([SyncedMeal].self, from: data)) ?? []
    }

    public static func loadGoal() -> SyncedGoal? {
        guard let data = SharedStore.defaults.data(forKey: goalKey) else { return nil }
        return try? decoder.decode(SyncedGoal.self, from: data)
    }
}
