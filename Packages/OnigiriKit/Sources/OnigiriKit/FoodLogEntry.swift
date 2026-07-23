import Foundation

/// One component of a logged meal, snapshotted INTO the log entry at
/// write time (correlation metadata, the OnigiriQuantity pattern):
/// resolving the meal from the library at view time would lie after
/// the meal is edited or deleted. `kcal` is the component's share of
/// ONE meal portion — totals stored on the entry are multiplied by the
/// quantity, this basis is not.
public struct LoggedMealItem: Codable, Sendable, Hashable {
    public let name: String
    public let kcal: Double

    public init(name: String, kcal: Double) {
        self.name = name
        self.kcal = kcal
    }

    /// JSON string for the metadata slot (plist-typed values only).
    /// nil on empty or encode failure — a log must never fail over its
    /// breakdown garnish.
    public static func encoded(_ items: [LoggedMealItem]) -> String? {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty on absent/corrupt metadata — pre-feature meal logs simply
    /// have no breakdown.
    public static func decoded(from raw: String?) -> [LoggedMealItem] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([LoggedMealItem].self, from: data)) ?? []
    }
}

/// One logged eating event, as read back from HealthKit.
/// `id` is the HealthKit correlation UUID, usable for deletion.
public struct FoodLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let kcal: Double
    public let sodiumMg: Double
    public let date: Date
    /// Meal slot the entry belongs to. Stored with the entry when logged
    /// from the app; inferred from the time of day for entries without one
    /// (older logs, watch logs, other apps).
    public let category: FoodCategory
    /// Extended nutrients read back from the correlation's samples, so a
    /// deleted entry can be re-logged (undo) without losing detail.
    public let nutrients: NutrientValues
    /// False for entries another app saved — HealthKit refuses deletes
    /// from anyone but the saver (and this app's watch/phone twin), so
    /// the UI must not offer Edit/Delete on them.
    public let editable: Bool
    /// The logged item carried AI-estimate provenance (correlation
    /// metadata) — drives the ✨ mark on log rows.
    public let aiGenerated: Bool
    /// How many portions the entry's totals represent (correlation
    /// metadata). 1 for entries logged before the key existed or by
    /// other apps — the edit sheet divides by this to recover the
    /// per-portion values, so "3 hot dogs" edits as 3, not as one
    /// triple-sized serving.
    public let quantity: Double
    /// The meal composition snapshotted at log time (correlation
    /// metadata, per-portion basis) — empty for plain foods and for
    /// meals logged before the key existed. Non-empty drives the meal
    /// mark on log rows and the edit sheet's Contains section.
    public let mealItems: [LoggedMealItem]

    public init(
        id: UUID,
        name: String,
        kcal: Double,
        sodiumMg: Double,
        date: Date,
        category: FoodCategory? = nil,
        nutrients: NutrientValues = NutrientValues(),
        editable: Bool = true,
        aiGenerated: Bool = false,
        quantity: Double = 1,
        mealItems: [LoggedMealItem] = []
    ) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.date = date
        self.category = category ?? FoodCategory.slot(for: date)
        self.nutrients = nutrients
        self.editable = editable
        self.aiGenerated = aiGenerated
        self.quantity = quantity > 0 && quantity.isFinite ? quantity : 1
        self.mealItems = mealItems
    }
}

public extension Sequence<FoodLogEntry> {
    /// The day's combined extended nutrients (the day-detail screen).
    /// Fields nobody logged stay nil, so the UI can tell "none recorded"
    /// from an actual zero.
    var totalNutrients: NutrientValues {
        reduce(NutrientValues()) { $0 + $1.nutrients }
    }

    /// Newest first, one entry per food name (case- and whitespace-
    /// insensitive), capped at `limit` — the Log sheet's Recent section.
    func uniquedByName(limit: Int) -> [FoodLogEntry] {
        var seen = Set<String>()
        var recents: [FoodLogEntry] = []
        for entry in sorted(by: { $0.date > $1.date }) {
            let key = entry.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            recents.append(entry)
            if recents.count == limit { break }
        }
        return recents
    }
}
