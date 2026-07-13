import SwiftUI
import OnigiriKit

/// The browsed day's full nutrient breakdown — everything the log wrote to
/// Health, finally on screen. Headline calories/sodium/water come from the
/// all-sources day summary; the macro and micronutrient sums come from the
/// app's own entries, so food logged by other apps counts up top but not
/// in the breakdown.
struct DayNutritionView: View {
    let model: TodayModel
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"

    private var totals: NutrientValues { model.foodLog.totalNutrients }

    var body: some View {
        List {
            summarySection
            if model.foodLog.isEmpty {
                Text(model.isToday ? "Nothing logged — log a meal to see its nutrients here." : "Nothing logged this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if totals.isEmpty {
                Text("Entries have no additional nutrient data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Collapsed by default, like the Log's meal sections:
                // the summary reads at a glance, the deep detail is a tap.
                Section {
                    if hasMacros {
                        DisclosureGroup("Macronutrients") { macroRows }
                    }
                    microGroup("Minerals", Micronutrient.minerals)
                    microGroup("Vitamins", Micronutrient.vitamins)
                }
            }
        }
        .readableContentWidth()
        .navigationTitle("Details")
    }

    private var dayLabel: String {
        if model.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day())
    }

    private var summarySection: some View {
        Section(dayLabel) {
            // The same icons these numbers wear on Today.
            iconRow("Calories", icon: { FoodIconView(raw: foodIcon) }) {
                Text("\(model.summary.intakeKcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            iconRow("Active burn", icon: { Image(systemName: "flame.fill").foregroundStyle(.red) }) {
                Text("\(model.summary.activeBurnKcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            iconRow("Resting burn", icon: { Image(systemName: "bed.double.fill").foregroundStyle(.indigo) }) {
                Text("\(model.summary.restingBurnKcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            // Same vocabulary as the calendar day card: positive is a
            // deficit (good), negative reads as a surplus. No icon on
            // Today either — it's a derived number.
            LabeledContent("Deficit") {
                let deficit = -model.summary.balanceKcal
                Text(deficit >= 0
                    ? "\(deficit, format: .number.precision(.fractionLength(0))) kcal"
                    : "\(-deficit, format: .number.precision(.fractionLength(0))) kcal surplus")
                    .foregroundStyle(deficit >= 0 ? Color.green : Color.orange)
                    .monospacedDigit()
            }
            iconRow("Sodium", icon: { Text("🧂") }) {
                Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) / \(sodiumLimitMg, format: .number.precision(.fractionLength(0))) mg")
                    .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                    .monospacedDigit()
            }
            iconRow("Water", icon: { WaterIconView(raw: waterIcon) }) {
                Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) / \(waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                    .foregroundStyle(model.summary.waterOz >= waterGoalOz ? Color.green : Color.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// A LabeledContent whose label wears Today's icon for the metric,
    /// in a fixed-width slot so the text column stays aligned.
    private func iconRow(
        _ title: String,
        @ViewBuilder icon: () -> some View,
        @ViewBuilder value: () -> some View
    ) -> some View {
        LabeledContent {
            value()
        } label: {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 24, alignment: .center)
                Text(title)
            }
        }
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

    /// One micronutrient group; disappears entirely when the day recorded
    /// nothing in it.
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
    /// (nil ≠ zero — zero grams is a real recorded amount).
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
