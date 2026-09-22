import Foundation

/// Is a database row the same food an ESTIMATE just named?
///
/// The offer this decides (`plans/PLAN-nutrition-plausibility.md`,
/// Layer 4) only helps if it is nearly always right: a published figure
/// shown beside an estimate carries more authority than the estimate,
/// so offering the wrong product is worse than offering nothing at all.
/// This is therefore deliberately conservative, and it refuses far more
/// than it accepts.
///
/// The rule, in one line: **every significant word the estimate used has
/// to appear in the candidate, and what the candidate adds must not turn
/// it into a different food.**
///
/// That asymmetry is the whole design. A brand prefix is welcome —
/// "Big Mac" against "McDonald's Big Mac" is the case worth having,
/// since the evals show the model over-estimating exactly those. But
/// "two large scrambled eggs" cannot match a row called "Eggs": a
/// composed dish is not the ingredient it was made from, and describe-it
/// exists precisely because no database holds one.
public enum PublishedNameMatch {
    /// Words that carry no identity, so their absence on either side
    /// proves nothing.
    static let ignored: Set<String> = [
        "the", "and", "with", "for", "from", "your", "our",
        "fresh", "raw", "whole", "plain", "style", "brand",
    ]

    /// Words whose ARRIVAL changes the food. A candidate may add a brand
    /// or a size; it may not add one of these and still claim to be the
    /// thing the estimate named. "Big Mac" is not "Big Mac Sauce".
    static let differentFood: Set<String> = [
        "sauce", "dressing", "seasoning", "syrup", "powder", "mix",
        "flavored", "flavoured", "flavor", "flavour", "scented",
        "candle", "gum", "concentrate", "extract", "kit", "spread",
        "topping", "marinade", "rub", "drink", "soda", "juice",
    ]

    /// At most this many words may be added — enough for a brand and a
    /// size ("McDonald's Big Mac Meal"), not enough to describe a
    /// different product.
    static let maximumAddedWords = 3

    /// Estimates longer than this are composed dishes, and a database
    /// row that "matches" one is a coincidence.
    static let maximumEstimateWords = 5

    public static func words(_ name: String) -> [String] {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !ignored.contains($0) }
    }

    public static func matches(estimate: String, candidate: String) -> Bool {
        let wanted = words(estimate)
        let found = Set(words(candidate))
        guard !wanted.isEmpty, !found.isEmpty else { return false }
        guard wanted.count <= maximumEstimateWords else { return false }
        // Every word the estimate used, present.
        guard Set(wanted).isSubset(of: found) else { return false }
        let added = found.subtracting(wanted)
        guard added.count <= maximumAddedWords else { return false }
        guard added.isDisjoint(with: differentFood) else { return false }
        return true
    }

    /// The best row to offer, or nil. First match in the source's own
    /// ranking order — the database's relevance beats any re-scoring
    /// invented here, and a second-best "close enough" is exactly the
    /// kind of offer that shouldn't be made.
    public static func best(
        for estimate: String, among candidates: [(name: String, product: ScannedProduct)]
    ) -> ScannedProduct? {
        candidates.first { matches(estimate: estimate, candidate: $0.name) }?.product
    }
}
