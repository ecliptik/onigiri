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

    private var totals: NutrientValues { model.foodLog.totalNutrients }

    var body: some View {
        List {
            summarySection
            if model.foodLog.isEmpty {
                Text(model.isToday ? "Nothing logged yet — log a meal to see its nutrients here." : "Nothing was logged this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if totals.isEmpty {
                Text("Entries are missing additional nutrients information")
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
        .navigationTitle("Nutrition")
    }

    private var dayLabel: String {
        if model.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day())
    }

    private var summarySection: some View {
        Section(dayLabel) {
            LabeledContent("Calories") {
                Text("\(model.summary.intakeKcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            LabeledContent("Sodium") {
                Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) / \(sodiumLimitMg, format: .number.precision(.fractionLength(0))) mg")
                    .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                    .monospacedDigit()
            }
            LabeledContent("Water") {
                Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) / \(waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                    .foregroundStyle(model.summary.waterOz >= waterGoalOz ? Color.green : Color.secondary)
                    .monospacedDigit()
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
