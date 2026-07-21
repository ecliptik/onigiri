import Foundation

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
        quantity: Double = 1
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
