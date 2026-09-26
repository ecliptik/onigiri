import Foundation

/// How a food's nutrition changes when its SERVING does.
///
/// A food's figures are per serving, and the serving is free text — so
/// retyping it relabels the food without touching a number. An online
/// row arrived as "1.0g" at 5.6 kcal; the serving was corrected to
/// "100", and the entry logged at 6 kcal, the form never having said
/// what 100 of those would come to (the user, 2026-09-25). This reads
/// both servings as amounts and gives the factor between them, so the
/// form can show the result and offer to apply it. It never applies
/// anything itself: a changed serving is as often a relabel as a
/// resize, and only the person typing knows which.
public enum ServingRescale {
    public enum Dimension: Sendable, Equatable { case mass, volume }

    /// A serving read as a measured amount, in grams or millilitres.
    public struct Amount: Sendable, Equatable {
        public let base: Double
        /// nil for a bare number, which borrows the other serving's unit.
        public let dimension: Dimension?
        /// What the unit was written as, for giving a bare number one.
        public let unit: String?
    }

    /// The factor that takes nutrition written for `from` to `to`, or
    /// nil when the two can't be compared — no amount in one of them,
    /// mass against volume (no density is guessed), or no change.
    public static func factor(from: String, to: String) -> Double? {
        guard let old = amount(in: from), let new = amount(in: to) else { return nil }
        if let a = old.dimension, let b = new.dimension, a != b { return nil }
        // A bare number takes the other side's unit — "1.0g" → "100"
        // means 100 g — so it converts with the unit it borrows. Two
        // bare counts ("1" → "2") compare as they stand.
        let oldBase = old.dimension == nil ? borrowed(old, unit: new.unit) : old.base
        let newBase = new.dimension == nil ? borrowed(new, unit: old.unit) : new.base
        guard oldBase > 0, newBase > 0 else { return nil }
        let factor = newBase / oldBase
        guard abs(factor - 1) > 0.0001 else { return nil }
        return factor
    }

    /// `to` with a unit, when it was a bare number and `from` had one —
    /// "100" after "1.0g" is "100 g", and a serving that says only "100"
    /// means nothing on a portion sheet later.
    public static func completed(_ to: String, after from: String) -> String {
        guard let new = amount(in: to), new.dimension == nil,
              let unit = amount(in: from)?.unit else { return to }
        return "\(to.trimmingCharacters(in: .whitespaces)) \(unit)"
    }

    /// The serving's amount: a bracketed measure first ("1 cup (240
    /// ml)" is 240 ml — the bracket is the label's own conversion), then
    /// the first number with a unit, then a lone number.
    public static func amount(in text: String) -> Amount? {
        let lowered = text.lowercased().replacingOccurrences(of: ",", with: ".")
        if let bracket = lowered.firstMatch(of: /\(([^)]*)\)/),
           let measured = measured(in: String(bracket.1)) {
            return measured
        }
        if let measured = measured(in: lowered) { return measured }
        let trimmed = lowered.trimmingCharacters(in: .whitespaces)
        if let bare = Double(trimmed), bare > 0 {
            return Amount(base: bare, dimension: nil, unit: nil)
        }
        return nil
    }

    private static func measured(in text: String) -> Amount? {
        let pattern = /(\d+(?:\.\d+)?)\s*(fl\.?\s*oz|kg|mg|g|grams?|ml|l|litres?|liters?|oz|ounces?|lbs?|pounds?)\b/
        guard let match = text.firstMatch(of: pattern), let value = Double(match.1) else { return nil }
        let unit = String(match.2).replacingOccurrences(of: " ", with: "")
        guard let (factor, dimension) = units[unit] ?? units[canonical(unit)] else { return nil }
        return Amount(base: value * factor, dimension: dimension, unit: display(unit))
    }

    private static func borrowed(_ amount: Amount, unit: String?) -> Double {
        guard let unit, let (factor, _) = units[canonical(unit)] else { return amount.base }
        return amount.base * factor
    }

    private static let units: [String: (Double, Dimension)] = [
        "mg": (0.001, .mass), "g": (1, .mass), "kg": (1000, .mass),
        "oz": (28.3495, .mass), "lb": (453.592, .mass),
        "ml": (1, .volume), "l": (1000, .volume), "floz": (29.5735, .volume),
    ]

    private static func canonical(_ unit: String) -> String {
        switch unit {
        case "gram", "grams": "g"
        case "litre", "litres", "liter", "liters": "l"
        case "ounce", "ounces": "oz"
        case "lbs", "pound", "pounds": "lb"
        case "fl.oz", "floz": "floz"
        default: unit
        }
    }

    private static func display(_ unit: String) -> String {
        switch canonical(unit) {
        case "floz": "fl oz"
        default: canonical(unit)
        }
    }
}
