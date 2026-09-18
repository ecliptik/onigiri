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
    /// The composer's "Estimate with AI" button, bumped — see
    /// `TapToEstimateRow.startToken`. Both hosts of this section have a
    /// composer, so both pass one; the idle row is gone from the list.
    var startToken: Binding<UUID?>?
    /// Raised while inference runs so the composer's button can say so
    /// and refuse a second tap.
    var isEstimating: Binding<Bool>?
    let onPick: (ScannedProduct) -> Void

    // A real Section, like OnlineResultsSection's own (no header, same
    // reason: "just the two choices to describe with AI or search"
    // reads as one flow, not two groups). Without one, `TapToEstimateRow`
    // is a bare row — fine mid-list, but this row now LEADS the Log
    // sheet's and the Add Food form's search results (2026-09-17, both
    // hosts' `.searchable` drawer having moved into the door bar), and a
    // bare row sitting first gets none of a Section's own top spacing —
    // it sat flush against the nav bar (the user, from device, dark
    // mode: "too close to the header"). The Section boundary is what
    // supplies the standard gap; a hardcoded `.padding(.top)` would only
    // approximate it and drift the moment List's own spacing changes.
    var body: some View {
        Section {
            TapToEstimateRow(
                query: query,
                // GENERIC, with the provider named in the RESULT
                // instead (the user, 2026-09-17). PLAN-unified-search's
                // amendment 1 put the provider here on 2026-07-20
                // because a bare "Estimate" didn't read as AI — "with
                // AI" keeps that much — and because for a REMOTE engine
                // it disclosed where the typed text was about to go
                // before you tapped. That disclosure now arrives with
                // the answer (`resultRow`'s caption is the engine that
                // actually replied), which is the accepted cost: the
                // provider is the user's own setting, chosen in
                // Settings, on a single-person app.
                title: "Estimate with AI",
                isEstimating: isEstimating,
                startToken: startToken,
                estimate: { await FoodIntelligence.describeFood($0) },
                // The typed description is the grounding, so a note
                // corrects the answer instead of restarting from a
                // longer sentence (`plans/PLAN-refine-with-context.md`).
                // describe-it never had a containment guard — the
                // person typed the food — so nothing is relaxed here.
                refine: { food, note in
                    await FoodIntelligence.refineEstimate(
                        prior: FoodIntelligence.RefinedFood(food),
                        grounding: .description(query),
                        note: note
                    )?.describedFood
                }
            ) { food in
                Button {
                    onPick(product(from: food))
                } label: {
                    resultRow(food)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Name + provider caption, kcal/sodium trailing — the online-row
    /// grammar, with the provenance where the brand line would sit.
    private func resultRow(_ food: FoodIntelligence.DescribedFood) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .foregroundStyle(.primary)
                // The engine that ANSWERED, not the one selected: an
                // unreachable provider hands off to Apple Intelligence,
                // and this caption is the only thing that says where the
                // numbers came from. (The row's TITLE above still names
                // the selection — that's a description of what tapping
                // will do, before anything has happened.)
                Text(food.engine.estimateCaption)
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
            aiGenerated: true,
            aiEngine: food.engine)
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
            // Generic, like the composer's "Estimate with AI" (the user,
            // 2026-09-18: "Match AI copy to be consistent"). The PROVIDER
            // is what came out of the label, not the object — this row
            // still says which thing it estimates, because the meal
            // builder also has a ✨ name button one row up. The provider
            // is named in the RESULT instead, where it is the engine that
            // actually replied rather than the one configured.
            title: "Estimate this meal with AI",
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
                // See the food row: the engine that answered.
                Text(meal.engine.estimateCaption)
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
