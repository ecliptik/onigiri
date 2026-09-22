import Foundation

/// The caption under a row of the meal builder's "In this meal" section.
///
/// A member row answers what it puts INTO the meal, not what one serving
/// of it is worth — the builder's Total is a sum of these, and a row
/// reading "190 kcal" while contributing 380 made the Total look wrong
/// (the user, 2026-08-09). The per-serving figure is still the useful
/// second clause, so it trails whenever the row isn't exactly one
/// serving.
///
/// Pure and here rather than in the view because BOTH row kinds — a
/// library pick and a component a described meal will mint — render
/// through it, and the one rule they share is the one thing that must
/// not drift between them.
public enum MealMemberCaption {
    /// At most two clauses, always contribution-first:
    /// - one serving → `220 kcal`, or `220 kcal · 1 cup` when a portion
    ///   is known (an estimate's portion; library foods pass none);
    /// - any other quantity → `380 kcal · 190 each`, where the
    ///   per-serving figure earns the slot over the portion text.
    public static func text(
        quantity: Double, kcalEach: Double, portion: String = ""
    ) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0))
        let contribution = "\((quantity * kcalEach).formatted(format)) kcal"
        // Fuzzy, not ==: quantities arrive from a 0.25-step stepper and
        // a typed decimal field, so exact equality on a Double is the
        // wrong test for "one serving".
        guard abs(quantity - 1) > 0.001 else {
            let trimmed = portion.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? contribution : "\(contribution) · \(trimmed)"
        }
        return "\(contribution) · \(kcalEach.formatted(format)) each"
    }
}
