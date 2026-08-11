import SwiftUI
import OnigiriKit

/// Macros and micronutrients for a set of `NutrientValues` — the day's
/// log, or a meal being assembled.
///
/// Extracted from `DayNutritionView` so the meal builder can show the
/// same breakdown rather than growing its own: two lists of the same
/// nutrients, formatted two ways, is exactly the drift the shared
/// `OnlineResultsSection` was made to stop.
///
/// Emits ROWS, not a Section, so each host decides its own container —
/// the day view groups them under one section with a provenance footer,
/// the meal builder puts them behind a single disclosure.
struct NutrientBreakdown: View {
    let totals: NutrientValues

    var body: some View {
        if hasMacros {
            DisclosureGroup("Macronutrients") { macroRows }
        }
        microGroup("Minerals", Micronutrient.minerals)
        microGroup("Vitamins", Micronutrient.vitamins)
    }

    private var hasMacros: Bool {
        [totals.fatG, totals.saturatedFatG, totals.transFatG,
         totals.polyunsaturatedFatG, totals.monounsaturatedFatG,
         totals.cholesterolMg, totals.carbsG, totals.fiberG,
         totals.sugarG, totals.proteinG, totals.caffeineMg]
            .contains { $0 != nil }
    }

    @ViewBuilder
    private var macroRows: some View {
        amountRow("Fat", totals.fatG, "g")
        amountRow("Saturated", totals.saturatedFatG, "g", indented: true)
        amountRow("Trans", totals.transFatG, "g", indented: true)
        amountRow("Polyunsaturated", totals.polyunsaturatedFatG, "g", indented: true)
        amountRow("Monounsaturated", totals.monounsaturatedFatG, "g", indented: true)
        amountRow("Cholesterol", totals.cholesterolMg, "mg")
        amountRow("Carbohydrates", totals.carbsG, "g")
        amountRow("Fiber", totals.fiberG, "g", indented: true)
        amountRow("Sugar", totals.sugarG, "g", indented: true)
        amountRow("Protein", totals.proteinG, "g")
        amountRow("Caffeine", totals.caffeineMg, "mg")
    }

    /// One micronutrient group; disappears entirely when nothing in it
    /// was recorded.
    @ViewBuilder
    private func microGroup(_ title: String, _ group: [Micronutrient]) -> some View {
        let present = group.compactMap { micro in
            totals[micro].map { (micro, $0) }
        }
        if !present.isEmpty {
            DisclosureGroup(title) {
                ForEach(present, id: \.0) { micro, value in
                    amountRow(micro.displayName, value, micro.unit.symbol)
                }
            }
        }
    }

    /// A nutrient row; renders nothing when the value was never logged
    /// (nil ≠ zero — zero grams is a real recorded amount). Do not
    /// "improve" this into showing 0: a meal of foods with patchy data
    /// would sprout a wall of zeros it never measured.
    @ViewBuilder
    private func amountRow(_ label: String, _ value: Double?, _ unit: String, indented: Bool = false) -> some View {
        if let value {
            LabeledContent {
                Text("\(value, format: .number.precision(.fractionLength(0...1))) \(unit)")
                    .monospacedDigit()
            } label: {
                Text(label)
                    .padding(.leading, indented ? 20 : 0)
                    .foregroundStyle(indented ? .secondary : .primary)
            }
        }
    }
}
