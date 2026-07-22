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
    /// The phone's plan inputs: its 14-day average burn and latest weight.
    /// The watch prefers these while fresh — its own Health store purges
    /// old samples, so a locally computed average runs over a shorter
    /// window and the two devices' budgets drift. Day-stamped (not
    /// time-stamped) so an unchanged value hashes identically and the
    /// phone's send-skip fingerprint still works. nil = keep.
    public let planBurnKcal: Double?
    public let planBurnDay: String?
    public let planWeightLb: Double?
    public let planWeightDay: String?
    /// When the phone last saw a Health log write (epoch seconds). Rides
    /// the context so a phone log's push wakes the watch complications —
    /// HealthKit's own sync carries the sample, but its background
    /// delivery is capped hourly on watchOS. nil = keep.
    public let lastLogAt: Double?

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
        sodiumLimitMg: Double? = nil,
        planBurnKcal: Double? = nil,
        planBurnDay: String? = nil,
        planWeightLb: Double? = nil,
        planWeightDay: String? = nil,
        lastLogAt: Double? = nil
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
        self.planBurnKcal = planBurnKcal
        self.planBurnDay = planBurnDay
        self.planWeightLb = planWeightLb
        self.planWeightDay = planWeightDay
        self.lastLogAt = lastLogAt
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
    static let planBurnKey = "sync.planBurnKcal"
    static let planBurnDayKey = "sync.planBurnDay"
    static let planWeightKey = "sync.planWeightLb"
    static let planWeightDayKey = "sync.planWeightDay"
    /// On the phone this is the stamp's origin (set on every observed
    /// Health log write); on the watch it's the synced copy. Same key,
    /// different stores.
    public static let lastLogAtKey = "sync.lastLogAt"

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

    /// Unit preferences ride the same stringified settings dict — but
    /// ALWAYS send, with an explicit "auto" when unset: a ride-only-when-
    /// set key would leave a stale explicit choice (say, kg) alive on the
    /// watch after the phone resets to Automatic.
    public static var unitPreferenceKeys: [String] { [
        SharedStore.weightUnitKey, SharedStore.waterUnitKey, SharedStore.sodiumUnitKey,
    ] }

    // MARK: Phone side

    public static func makeContext(
        meals: [SyncedMeal],
        recentFoods: [SyncedMeal] = [],
        favorites: [SyncedMeal] = [],
        goal: SyncedGoal?,
        waterServingOz: Double,
        waterGoalOz: Double,
        balanceStyle: String = "remaining",
        foodIcon: String = "sfFork",
        waterIcon: String = "sfDrop",
        rewardIcon: String = "onigiri",
        trackedMetricSettings: [String: String] = [:],
        sodiumLimitMg: Double = 2300,
        planBurnKcal: Double? = nil,
        planBurnDay: String? = nil,
        planWeightLb: Double? = nil,
        planWeightDay: String? = nil,
        lastLogAt: Double? = nil
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
        if let planBurnKcal, let planBurnDay {
            context[planBurnKey] = planBurnKcal
            context[planBurnDayKey] = planBurnDay
        }
        if let planWeightLb, let planWeightDay {
            context[planWeightKey] = planWeightLb
            context[planWeightDayKey] = planWeightDay
        }
        if let lastLogAt {
            context[lastLogAtKey] = lastLogAt
        }
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
            sodiumLimitMg: context[SharedStore.sodiumLimitKey] as? Double,
            planBurnKcal: context[planBurnKey] as? Double,
            planBurnDay: context[planBurnDayKey] as? String,
            planWeightLb: context[planWeightKey] as? Double,
            planWeightDay: context[planWeightDayKey] as? String,
            lastLogAt: context[lastLogAtKey] as? Double
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
        // Value and day land together (makeContext pairs them) — a value
        // without its day would look eternally fresh or eternally stale.
        if let burn = payload.planBurnKcal, let day = payload.planBurnDay {
            defaults.set(burn, forKey: planBurnKey)
            defaults.set(day, forKey: planBurnDayKey)
        }
        if let weight = payload.planWeightLb, let day = payload.planWeightDay {
            defaults.set(weight, forKey: planWeightKey)
            defaults.set(day, forKey: planWeightDayKey)
        }
        if let stamp = payload.lastLogAt {
            defaults.set(stamp, forKey: lastLogAtKey)
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

    /// The phone's synced plan inputs, day stamps included — the loader
    /// judges freshness through `isRecentDay`.
    public static func syncedPlanBurn() -> (kcal: Double, day: String)? {
        let defaults = SharedStore.defaults
        guard let kcal = defaults.object(forKey: planBurnKey) as? Double,
              let day = defaults.string(forKey: planBurnDayKey) else { return nil }
        return (kcal, day)
    }

    public static func syncedPlanWeight() -> (lb: Double, day: String)? {
        let defaults = SharedStore.defaults
        guard let lb = defaults.object(forKey: planWeightKey) as? Double,
              let day = defaults.string(forKey: planWeightDayKey) else { return nil }
        return (lb, day)
    }

    /// When the phone last saw a Health log write. On the phone this reads
    /// the local stamp; on the watch, the synced copy.
    public static func lastPhoneLogAt() -> Date? {
        guard let stamp = SharedStore.defaults.object(forKey: lastLogAtKey) as? Double
        else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    /// Phone-side: a Health log just happened — stamp it so the next
    /// context push carries it and wakes the watch complications.
    public static func stampPhoneLog(at date: Date = .now) {
        SharedStore.defaults.set(date.timeIntervalSince1970, forKey: lastLogAtKey)
    }

    /// Today or yesterday, by calendar day — the freshness window for the
    /// phone's plan inputs. The phone re-stamps on every foreground, so
    /// anything older means the devices haven't talked; fall back to the
    /// watch's own store rather than trust a stale budget.
    static func isRecentDay(
        _ day: String, calendar: Calendar = .current, now: Date = .now
    ) -> Bool {
        if day == DeficitTargetHistory.dayKey(for: now, calendar: calendar) { return true }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        return day == DeficitTargetHistory.dayKey(for: yesterday, calendar: calendar)
    }
}
