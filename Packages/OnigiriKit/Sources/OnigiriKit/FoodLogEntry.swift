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

    public init(
        id: UUID,
        name: String,
        kcal: Double,
        sodiumMg: Double,
        date: Date,
        category: FoodCategory? = nil,
        nutrients: NutrientValues = NutrientValues()
    ) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.sodiumMg = sodiumMg
        self.date = date
        self.category = category ?? FoodCategory.slot(for: date)
        self.nutrients = nutrients
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
