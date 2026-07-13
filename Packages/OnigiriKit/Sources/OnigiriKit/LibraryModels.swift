import Foundation
import SwiftData

@Model
public final class Food {
    public var name: String
    public var kcal: Double
    public var sodiumMg: Double
    public var servingDescription: String
    public var barcode: String?
    public var createdAt: Date
    // Extended nutrients (grams; cholesterol/caffeine mg), optional.
    public var fatG: Double?
    public var saturatedFatG: Double?
    public var transFatG: Double?
    public var polyunsaturatedFatG: Double?
    public var monounsaturatedFatG: Double?
    public var cholesterolMg: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fiberG: Double?
    public var sugarG: Double?
    public var caffeineMg: Double?
    /// Vitamins & minerals in canonical units, keyed by Micronutrient
    /// rawValue. Optional so pre-existing stores migrate lightweight.
    public var micros: [String: Double]?
    // Library organization.
    public var isFavorite: Bool = false
    public var category: String?
    /// Bumped on every log — drives the recency sort under favorites.
    /// Optional so pre-existing stores migrate lightweight; nil reads
    /// as createdAt.
    public var lastUsedAt: Date?
    public var recencyDate: Date { lastUsedAt ?? createdAt }
    /// Inverse of MealItem.food (declared there): deleting a food nullifies
    /// the items that reference it instead of leaving a dangling pointer
    /// that traps SwiftData on the next property access.
    public var mealItems: [MealItem]

    public init(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        servingDescription: String = "",
        barcode: String? = nil,
        nutrients: NutrientValues = NutrientValues(),
        isFavorite: Bool = false,
        category: String? = nil
    ) {
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.servingDescription = servingDescription
        self.barcode = barcode
        self.createdAt = .now
        self.fatG = nutrients.fatG
        self.saturatedFatG = nutrients.saturatedFatG
        self.transFatG = nutrients.transFatG
        self.polyunsaturatedFatG = nutrients.polyunsaturatedFatG
        self.monounsaturatedFatG = nutrients.monounsaturatedFatG
        self.cholesterolMg = nutrients.cholesterolMg
        self.carbsG = nutrients.carbsG
        self.proteinG = nutrients.proteinG
        self.fiberG = nutrients.fiberG
        self.sugarG = nutrients.sugarG
        self.caffeineMg = nutrients.caffeineMg
        self.micros = nutrients.micros.isEmpty ? nil : nutrients.micros
        self.isFavorite = isFavorite
        self.category = category
        self.mealItems = []
    }

    public var nutrients: NutrientValues {
        get {
            NutrientValues(
                fatG: fatG, saturatedFatG: saturatedFatG, transFatG: transFatG,
                polyunsaturatedFatG: polyunsaturatedFatG,
                monounsaturatedFatG: monounsaturatedFatG,
                cholesterolMg: cholesterolMg, carbsG: carbsG, proteinG: proteinG,
                fiberG: fiberG, sugarG: sugarG, caffeineMg: caffeineMg,
                micros: micros ?? [:]
            )
        }
        set {
            fatG = newValue.fatG
            saturatedFatG = newValue.saturatedFatG
            transFatG = newValue.transFatG
            polyunsaturatedFatG = newValue.polyunsaturatedFatG
            monounsaturatedFatG = newValue.monounsaturatedFatG
            cholesterolMg = newValue.cholesterolMg
            carbsG = newValue.carbsG
            proteinG = newValue.proteinG
            fiberG = newValue.fiberG
            sugarG = newValue.sugarG
            caffeineMg = newValue.caffeineMg
            micros = newValue.micros.isEmpty ? nil : newValue.micros
        }
    }
}

@Model
public final class MealItem {
    @Relationship(inverse: \Food.mealItems)
    public var food: Food?
    /// Inverse of `Meal.items` — without it, deleting an item that a
    /// meal still references leaves a dangling reference that kills the
    /// process on the next `items` access (same class of crash as the
    /// Food↔MealItem incident).
    public var meal: Meal?
    public var quantity: Double

    public init(food: Food, quantity: Double = 1) {
        self.food = food
        self.quantity = quantity
    }

    public var kcal: Double { (food?.kcal ?? 0) * quantity }
    public var sodiumMg: Double { (food?.sodiumMg ?? 0) * quantity }
}

@Model
public final class Meal {
    /// Stable external identifier, used by widget configuration entities.
    public var uuid: UUID
    public var name: String
    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal) public var items: [MealItem]
    public var createdAt: Date
    public var isFavorite: Bool = false
    public var category: String?
    /// Bumped on every log — drives the recency sort under favorites.
    public var lastUsedAt: Date?
    public var recencyDate: Date { lastUsedAt ?? createdAt }

    public init(name: String, items: [MealItem], isFavorite: Bool = false, category: String? = nil) {
        self.uuid = UUID()
        self.name = name
        self.items = items
        self.createdAt = .now
        self.isFavorite = isFavorite
        self.category = category
    }

    public var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var totalSodiumMg: Double { items.reduce(0) { $0 + $1.sodiumMg } }
    public var totalNutrients: NutrientValues {
        items.reduce(NutrientValues()) { partial, item in
            partial + (item.food?.nutrients.scaled(by: item.quantity) ?? NutrientValues())
        }
    }
}

@Model
public final class GoalSettings {
    public var targetWeightLb: Double
    public var targetDate: Date
    /// Manual fallback when Apple Health has no weight samples yet.
    public var fallbackCurrentWeightLb: Double?

    public init(
        targetWeightLb: Double,
        targetDate: Date,
        fallbackCurrentWeightLb: Double? = nil
    ) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
    }
}

/// The duplicate-food guard's name matching: scanning a product whose
/// name is already in the library should offer editing it, not mint a
/// twin. Case- and whitespace-insensitive equality — deliberately not
/// fuzzy (see PLAN-1.2).
public enum LibraryDuplicate {
    public static func nameMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces)
            .localizedCaseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }
}

/// Storage shared between the app and its widget extension via the App Group.
public enum SharedStore {
    public static let appGroupID = "group.com.ecliptik.Onigiri"

    public static let waterServingKey = "waterServingOz"
    public static let waterGoalKey = "waterGoalOz"
    public static let waterIconKey = "waterIcon"
    public static let foodIconKey = "foodIcon"
    public static let rewardIconKey = "rewardIcon"
    public static let sodiumLimitKey = "sodiumLimitMg"
    public static let balanceStyleKey = "balanceStyle"
    public static let progressGaugesKey = "progressGauges"
    public static let showSodiumKey = "showSodium"
    public static let showWaterKey = "showWater"
    public static let remindMealsKey = "remindMeals"
    public static let remindWaterKey = "remindWater"
    public static let remindStreakKey = "remindStreak"
    // Today's two tracked-metric slots (historically sodium and water —
    // those defaults keep pre-feature installs unchanged).
    public static let trackedMetric1Key = "trackedMetric1"
    public static let trackedMetric1ModeKey = "trackedMetric1Mode"
    public static let trackedMetric1TargetKey = "trackedMetric1Target"
    public static let trackedMetric1IconKey = "trackedMetric1Icon"
    public static let trackedMetric2Key = "trackedMetric2"
    public static let trackedMetric2ModeKey = "trackedMetric2Mode"
    public static let trackedMetric2TargetKey = "trackedMetric2Target"
    public static let trackedMetric2IconKey = "trackedMetric2Icon"
    /// The stored value that switches a slot off.
    public static let trackedMetricNone = "none"

    /// Slot 1 defaults to sodium, slot 2 to water; nil = "None" (off).
    public static func trackedNutrient(slot: Int) -> TrackedNutrient? {
        let key = defaults.string(forKey: slot == 1 ? trackedMetric1Key : trackedMetric2Key)
        if key == trackedMetricNone { return nil }
        return key.flatMap(TrackedNutrient.init(key:)) ?? (slot == 1 ? .sodium : .water)
    }

    public static func trackedMode(slot: Int, nutrient: TrackedNutrient) -> TrackedMetricMode {
        let raw = defaults.string(forKey: slot == 1 ? trackedMetric1ModeKey : trackedMetric2ModeKey)
        return raw.flatMap(TrackedMetricMode.init(rawValue:)) ?? nutrient.defaultMode
    }

    /// Sodium and water targets stay wired to their long-standing keys —
    /// the calendar day cards, nutrition detail, and water reminders all
    /// read those; one source of truth.
    public static func trackedTarget(slot: Int, nutrient: TrackedNutrient) -> Double {
        switch nutrient {
        case .sodium: return sodiumLimitMg
        case .water: return waterGoalOz
        default:
            let value = defaults.double(forKey: slot == 1 ? trackedMetric1TargetKey : trackedMetric2TargetKey)
            return value > 0 ? value : nutrient.defaultTarget
        }
    }

    /// The slot's display emoji: the custom pick, else the nutrient's
    /// default. Water renders through WaterIconView with the app-wide
    /// water icon instead; this is its text fallback.
    public static func trackedEmoji(slot: Int, nutrient: TrackedNutrient) -> String {
        let stored = defaults.string(forKey: slot == 1 ? trackedMetric1IconKey : trackedMetric2IconKey)
        return customEmoji(stored) ?? nutrient.defaultEmoji
    }

    /// A raw icon value resolved against a slot's nutrient default —
    /// the emoji-prompt prefill for metric icon slots.
    public static func customEmojiOrDefault(_ raw: String, for nutrient: TrackedNutrient?) -> String {
        customEmoji(raw) ?? nutrient?.defaultEmoji ?? "🙂"
    }

    /// What the big Today/watch number shows: "balance" (± intake − burn,
    /// default) or "remaining" (kcal left to eat toward the deficit goal).
    public static var showsRemainingKcal: Bool {
        defaults.string(forKey: balanceStyleKey) == "remaining"
    }

    /// Daily sodium limit in mg (FDA guideline 2,300 by default).
    public static var sodiumLimitMg: Double {
        let value = defaults.double(forKey: sodiumLimitKey)
        return value > 0 ? value : 2300
    }

    public static let untrackedBelowKey = "untrackedBelowKcal"
    /// "cards" (Intake/Active/Resting tiles, default) or "compact"
    /// (Burned/Eaten flanking the balance headline — frees a row for
    /// the log).
    public static let energyStatsStyleKey = "energyStatsStyle"
    /// First-run onboarding shown (or deliberately skipped) — existing
    /// installs with a goal are flagged true without seeing it.
    public static let hasOnboardedKey = "hasOnboarded"

    /// Days with less intake logged count as untracked — streak-breaking,
    /// excluded from month totals. Default 1,000; the user can set 0 to
    /// disable (so unset and explicit-zero must be distinguishable).
    public static var untrackedBelowKcal: Double {
        defaults.object(forKey: untrackedBelowKey) == nil
            ? 1000
            : defaults.double(forKey: untrackedBelowKey)
    }

    /// One visible character that presents as emoji — keeps letters and
    /// digits out of the icon slots while allowing any real emoji
    /// (multi-scalar sequences like flags and ZWJ families included).
    public static func isCustomEmoji(_ value: String) -> Bool {
        guard value.count == 1, let first = value.unicodeScalars.first else { return false }
        return first.properties.isEmoji
            && (first.properties.isEmojiPresentation
                || value.unicodeScalars.contains { $0.properties.isVariationSelector }
                || value.unicodeScalars.count > 1)
    }

    /// An icon slot's raw value that isn't a preset tag: the user's own
    /// emoji, stored verbatim.
    static func customEmoji(_ raw: String?) -> String? {
        raw.flatMap { isCustomEmoji($0) ? $0 : nil }
    }

    /// Water icon options; 💧 drop is the default; any custom emoji the
    /// user typed is stored as itself.
    public static func waterEmoji(for raw: String?) -> String {
        switch raw {
        case "wave": "🌊"
        case "cup": "🥤"
        case "tap": "🚰"
        case "pour": "🫗"
        case "ice": "🧊"
        default: customEmoji(raw) ?? "💧"
        }
    }

    public static var waterEmoji: String {
        waterEmoji(for: defaults.string(forKey: waterIconKey))
    }

    /// The food icon used everywhere content means "food/intake" —
    /// 🍎 by default; 🍙 stays the reward mark, not a food icon.
    public static func foodEmoji(for raw: String?) -> String {
        switch raw {
        case "onigiri": "🍙"
        case "plate": "🍽️"
        case "bento": "🍱"
        case "noodles": "🍜"
        case "fork": "🍴"
        default: customEmoji(raw) ?? "🍎"
        }
    }

    public static var foodEmoji: String {
        foodEmoji(for: defaults.string(forKey: foodIconKey))
    }

    /// The earned-goal badge shown on Today, the calendar, and the
    /// complications; 🍙 by default. The onigiri stays the app's logo and
    /// name regardless of this choice.
    public static func rewardEmoji(for raw: String?) -> String {
        switch raw {
        case "trophy": "🏆"
        case "medal": "🥇"
        case "star": "⭐️"
        case "fire": "🔥"
        case "muscle": "💪"
        case "target": "🎯"
        case "sparkles": "✨"
        default: customEmoji(raw) ?? "🍙"
        }
    }

    public static var rewardEmoji: String {
        rewardEmoji(for: defaults.string(forKey: rewardIconKey))
    }

    /// ONE shared instance, deliberately. This was a computed property
    /// minting a fresh UserDefaults per access — @AppStorage observes the
    /// specific instance it's given, and cross-instance KVO fires on the
    /// simulator but not reliably on device, so Settings toggles wrote
    /// through one instance while Today listened on another and never
    /// heard the change.
    /// nonisolated(unsafe): UserDefaults is documented thread-safe; it
    /// just predates Sendable.
    public nonisolated(unsafe) static let defaults = UserDefaults(suiteName: appGroupID) ?? .standard

    public static var waterServingOz: Double {
        let value = defaults.double(forKey: waterServingKey)
        return value > 0 ? value : 12
    }

    public static var waterGoalOz: Double {
        let value = defaults.double(forKey: waterGoalKey)
        return value > 0 ? value : 64
    }

    /// Where the shared SwiftData store lives inside the App Group.
    public static var storeURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Onigiri.sqlite")
    }

    /// SwiftData container in the App Group so widgets can read the library.
    /// Falls back to the default location if the entitlement is missing.
    public static func modelContainer() throws -> ModelContainer {
        let schema = Schema([Food.self, Meal.self, GoalSettings.self])
        if let url = storeURL {
            let config = ModelConfiguration(url: url)
            return try ModelContainer(for: schema, configurations: [config])
        }
        return try ModelContainer(for: schema, configurations: [ModelConfiguration()])
    }
}
