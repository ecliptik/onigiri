import SwiftUI
import OnigiriKit

/// The tap-to-estimate row that leads every FOOD search-result list
/// (PLAN-unified-search): "✨ Estimate with <provider>". Picking hands the
/// host a ScannedProduct — the same currency as an online pick, so every
/// host routes it with paths it already has (the full food form from the
/// Log sheet and Foods, apply() on the form itself).
///
/// The phase machine and its four hard-won behaviors live in
/// `TapToEstimateRow`, shared with `MealEstimateSection`.
struct AIEstimateSection: View {
    let query: String
    let onPick: (ScannedProduct) -> Void

    var body: some View {
        TapToEstimateRow(
            query: query,
            title: "Estimate with \(AIProviderSettings.selected.displayName)",
            estimate: { await FoodIntelligence.describeFood($0) }
        ) { food in
            Button {
                onPick(product(from: food))
            } label: {
                resultRow(food)
            }
            .buttonStyle(.plain)
        }
    }

    /// Name + provider caption, kcal/sodium trailing — the online-row
    /// grammar, with the provenance where the brand line would sit.
    private func resultRow(_ food: FoodIntelligence.DescribedFood) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .foregroundStyle(.primary)
                Text(AIProviderSettings.selected.estimateCaption)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
                Text(TrackedNutrient.sodium.captionText(food.sodiumMg, sodium: SharedStore.sodiumUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
    }

    private func product(from food: FoodIntelligence.DescribedFood) -> ScannedProduct {
        ScannedProduct(
            barcode: "",
            name: food.name,
            kcal: food.kcal,
            sodiumMg: food.sodiumMg,
            servingDescription: food.serving,
            nutrients: food.nutrients,
            aiGenerated: true)
    }
}

/// The meal builder's tap-to-estimate row: describe a whole meal
/// ("chicken burrito bowl with rice, beans, and guac") and get its PARTS.
/// Same field, same grammar, same one-inference-per-tap rule as the food
/// row — the difference is what a pick delivers: a `DescribedMeal` whose
/// components the form reviews, matches against the library, and mints
/// only at Save.
struct MealEstimateSection: View {
    let query: String
    /// Raised while inference runs, so the form can quiet its ✨ name
    /// button — two concurrent calls serialize on-device and double-bill
    /// a BYO-AI provider.
    var isEstimating: Binding<Bool>?
    let onPick: (FoodIntelligence.DescribedMeal) -> Void

    var body: some View {
        TapToEstimateRow(
            query: query,
            title: "Estimate this meal with \(AIProviderSettings.selected.displayName)",
            isEstimating: isEstimating,
            estimate: { await FoodIntelligence.describeMeal($0) }
        ) { meal in
            Button {
                onPick(meal)
            } label: {
                resultRow(meal)
            }
            .buttonStyle(.plain)
        }
    }

    /// The meal, its provenance, and what accepting it costs — the part
    /// count answers "how much am I about to review?".
    private func resultRow(_ meal: FoodIntelligence.DescribedMeal) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .foregroundStyle(.primary)
                Text(AIProviderSettings.selected.estimateCaption)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
                Text(meal.components.count == 1 ? "1 item" : "\(meal.components.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}
