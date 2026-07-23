import Foundation
import Security
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
    /// Provenance: values came from an AI estimate (describe or photo
    /// identify) — drives the ✨ mark in library rows. Defaulted so
    /// pre-existing stores migrate lightweight.
    public var aiGenerated: Bool = false
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
        category: String? = nil,
        aiGenerated: Bool = false
    ) {
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.servingDescription = servingDescription
        self.barcode = barcode
        self.createdAt = .now
        self.aiGenerated = aiGenerated
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
    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal) public var items: [MealItem] = []
    public var createdAt: Date
    public var isFavorite: Bool = false
    public var category: String?
    /// Bumped on every log — drives the recency sort under favorites.
    public var lastUsedAt: Date?
    public var recencyDate: Date { lastUsedAt ?? createdAt }
    /// Provenance: the meal's name came from an AI suggestion — drives
    /// the ✨ mark. Defaulted so pre-existing stores migrate lightweight.
    public var aiGenerated: Bool = false

    public init(name: String, items: [MealItem], isFavorite: Bool = false, category: String? = nil, aiGenerated: Bool = false) {
        self.uuid = UUID()
        self.name = name
        self.items = items
        self.createdAt = .now
        self.isFavorite = isFavorite
        self.category = category
        self.aiGenerated = aiGenerated
    }

    public var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var totalSodiumMg: Double { items.reduce(0) { $0 + $1.sodiumMg } }
    public var totalNutrients: NutrientValues {
        items.reduce(NutrientValues()) { partial, item in
            partial + (item.food?.nutrients.scaled(by: item.quantity) ?? NutrientValues())
        }
    }

    /// The composition snapshot a log write records (per one meal
    /// portion) — each component's name and kcal share, quantities
    /// folded in ("2× Egg" contributes one line at doubled kcal, and
    /// the count rides the name so the breakdown reads naturally).
    public var loggedItems: [LoggedMealItem] {
        items.compactMap { item in
            guard let food = item.food else { return nil }
            let name = item.quantity == 1
                ? food.name
                : "\(item.quantity.formatted(.number.precision(.fractionLength(0...2))))× \(food.name)"
            return LoggedMealItem(name: name, kcal: item.kcal)
        }
    }
}

@Model
public final class GoalSettings {
    public var targetWeightLb: Double
    public var targetDate: Date
    /// Manual fallback when Apple Health has no weight samples yet.
    public var fallbackCurrentWeightLb: Double?
    /// GoalMode.lose (nil, the historical default) or .maintain — in
    /// maintenance the target/date are ignored and the budget is TDEE.
    public var mode: String?

    public init(
        targetWeightLb: Double,
        targetDate: Date,
        fallbackCurrentWeightLb: Double? = nil,
        mode: String? = nil
    ) {
        self.targetWeightLb = targetWeightLb
        self.targetDate = targetDate
        self.fallbackCurrentWeightLb = fallbackCurrentWeightLb
        self.mode = mode
    }

    public var isMaintenance: Bool { mode == GoalMode.maintain }
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
    public static let mealIconKey = "mealIcon"
    public static let sodiumLimitKey = "sodiumLimitMg"
    public static let balanceStyleKey = "balanceStyle"
    public static let progressGaugesKey = "progressGauges"
    public static let showSodiumKey = "showSodium"
    public static let showWaterKey = "showWater"
    public static let remindMealsKey = "remindMeals"
    public static let remindWaterKey = "remindWater"
    public static let remindStreakKey = "remindStreak"
    // Reminder times, minutes since midnight; absent = the planner's
    // original fixed schedule (ReminderPlanner.Times defaults).
    public static let remindMealsMinuteKey = "remindMealsMinute"
    public static let remindStreakMinuteKey = "remindStreakMinute"
    public static let remindWaterMinute1Key = "remindWaterMinute1"
    public static let remindWaterMinute2Key = "remindWaterMinute2"
    public static let remindWaterMinute3Key = "remindWaterMinute3"
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
        // Water is always a goal — "limit your water" isn't a thing this
        // app says, and Settings hides the Type picker for it.
        if nutrient == .water { return .goal }
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

    /// What the big Today/watch/widget number shows — see `HeadlineMode`.
    /// Unset/unknown reads as `.remaining` (the historical default).
    public static var headlineMode: HeadlineMode {
        HeadlineMode(rawValue: defaults.string(forKey: balanceStyleKey) ?? "") ?? .remaining
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

    /// Master switch for EVERY online food lookup — text search AND
    /// barcode lookups, OpenFoodFacts and USDA alike. OFF BY DEFAULT
    /// (the user, 2026-07-20: the whole privacy story is "nothing
    /// leaves the device until you say so"); onboarding offers it,
    /// Settings → Online Database owns it. Absent = OFF. With it off,
    /// search is library-only and the scanner reads labels only.
    public static let onlineLookupsKey = "onlineLookups"
    public static var onlineLookups: Bool {
        defaults.bool(forKey: onlineLookupsKey)
    }

    /// Text-search database: "off" (OpenFoodFacts, default), "fdc"
    /// (USDA FoodData Central), or "both" (one merged list). Barcode
    /// scans always use OpenFoodFacts.
    public static let textSearchSourceKey = "textSearchSource"
    public static let textSearchSourceOFF = "off"
    public static let textSearchSourceFDC = "fdc"
    public static let textSearchSourceBoth = "both"
    /// The user's api.data.gov key — device-local on purpose: it never
    /// rides WatchConnectivity (the watch doesn't search) and never
    /// enters the repo.
    public static let fdcAPIKeyKey = "fdcAPIKey"

    /// Holding the corner + logs a water serving — opt-out, default ON
    /// (absent means enabled, so existing installs get the feature).
    public static let holdToLogWaterKey = "holdToLogWater"
    public static var holdToLogWater: Bool {
        defaults.object(forKey: holdToLogWaterKey) == nil
            ? true
            : defaults.bool(forKey: holdToLogWaterKey)
    }

    // The FDC key is a credential, so it lives in the Keychain, not the
    // App Group defaults plist (which any process with the container can
    // read). AfterFirstUnlockThisDeviceOnly = encrypted at rest, readable
    // after the first unlock (so a backgrounded search still works), never
    // in a backup and never off this device — matching its long-standing
    // "device-local, never synced" intent.
    private static let fdcKeychainService = "com.ecliptik.Onigiri.fdc"
    private static let fdcKeychainAccount = "fdcAPIKey"

    private static func fdcKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: fdcKeychainService,
            kSecAttrAccount as String: fdcKeychainAccount,
        ]
    }

    /// The user's FDC key, trimmed; empty means "none saved". Reads the
    /// Keychain, migrating a value left in the legacy defaults slot on
    /// first read (then clearing the plaintext copy).
    public static var fdcAPIKey: String {
        if let stored = readFDCKeychain() { return stored }
        let legacy = (defaults.string(forKey: fdcAPIKeyKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            _ = writeFDCKeychain(legacy)
            defaults.removeObject(forKey: fdcAPIKeyKey)
            return legacy
        }
        return ""
    }

    /// Save (non-empty) or clear (empty) the FDC key in the Keychain. Also
    /// drops any legacy defaults copy so a plaintext key can't linger.
    @discardableResult
    public static func saveFDCAPIKey(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.removeObject(forKey: fdcAPIKeyKey)
        if key.isEmpty {
            SecItemDelete(fdcKeychainQuery() as CFDictionary)
            return true
        }
        return writeFDCKeychain(key)
    }

    private static func readFDCKeychain() -> String? {
        var query = fdcKeychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Upsert (update-then-add), never delete-then-add — the latter races
    /// and drops item metadata.
    @discardableResult
    private static func writeFDCKeychain(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(fdcKeychainQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = fdcKeychainQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    /// api.data.gov keys are 40 letters and digits; anything else is a
    /// mis-paste. Gates SAVING in Settings, not requests — the server
    /// still 403s a well-formed-but-wrong key, with actionable copy.
    public static func isPlausibleFDCKey(_ key: String) -> Bool {
        key.count == 40 && key.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// What a text search actually queries once the key is accounted
    /// for: fdc/both without a key fall back to OpenFoodFacts alone
    /// (the Settings hint says so).
    public enum TextSearchMode: Sendable, Equatable {
        case openFoodFacts, fdc, both
    }

    public static var textSearchMode: TextSearchMode {
        guard !fdcAPIKey.isEmpty else { return .openFoodFacts }
        switch defaults.string(forKey: textSearchSourceKey) {
        case textSearchSourceFDC: return .fdc
        case textSearchSourceBoth: return .both
        default: return .openFoodFacts
        }
    }

    /// Whether text search hits FDC at all (alone or merged).
    public static var usesFDCTextSearch: Bool {
        textSearchMode != .openFoodFacts
    }

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

    /// The mark beside meal names wherever meals mix with foods
    /// (Favorites, the Log sheet, Today's log) — 🍽️ by default, 🍱 the
    /// offered alternate (Appearance); a custom emoji stores as itself.
    public static func mealEmoji(for raw: String?) -> String {
        switch raw {
        case "plate": "🍽️"
        case "bento": "🍱"
        default: customEmoji(raw) ?? "🍽️"
        }
    }

    public static var mealEmoji: String {
        mealEmoji(for: defaults.string(forKey: mealIconKey))
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

    /// The user-tuned reminder times; keys never written read the
    /// planner's original fixed schedule (integer(forKey:) would turn
    /// an absent key into midnight).
    public static var reminderTimes: ReminderPlanner.Times {
        func minute(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }
        let original = ReminderPlanner.Times()
        return ReminderPlanner.Times(
            mealMinute: minute(remindMealsMinuteKey, original.mealMinute),
            streakMinute: minute(remindStreakMinuteKey, original.streakMinute),
            waterMinutes: [
                minute(remindWaterMinute1Key, original.waterMinutes[0]),
                minute(remindWaterMinute2Key, original.waterMinutes[1]),
                minute(remindWaterMinute3Key, original.waterMinutes[2]),
            ]
        )
    }

    /// Where the shared SwiftData store lives inside the App Group.
    public static var storeURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Onigiri.sqlite")
    }

    /// SwiftData container in the App Group so widgets can read the library.
    /// Falls back to the default location if the entitlement is missing.
    public static func modelContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OnigiriSchemaV1.self)
        if let url = storeURL {
            let config = ModelConfiguration(url: url)
            return try ModelContainer(
                for: schema, migrationPlan: OnigiriMigrationPlan.self, configurations: [config])
        }
        return try ModelContainer(
            for: schema, migrationPlan: OnigiriMigrationPlan.self,
            configurations: [ModelConfiguration()])
    }
}

/// The schema, versioned the moment App Store distribution came into
/// view (2026-07-20 audit): once stores live on strangers' devices
/// their historical diversity is permanent, and every store shipped so
/// far is describable as this one shape (all changes to date were
/// additive-with-default, aiGenerated included). Any future
/// NON-additive change gets a SchemaV2 + a real MigrationStage here —
/// never an in-place edit of V1.
/// NOTE: VersionedSchema.models gets NO transitive relationship
/// discovery — every model must be listed, MealItem included (the
/// plain Schema([...]) used to omit it and lean on discovery).
public enum OnigiriSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Food.self, MealItem.self, Meal.self, GoalSettings.self]
    }
}

public enum OnigiriMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [OnigiriSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
