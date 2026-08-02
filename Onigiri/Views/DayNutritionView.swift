import SwiftUI
import OnigiriKit

/// The browsed day's full nutrient breakdown — everything the log wrote to
/// Health, finally on screen. Headline calories/sodium/water come from the
/// all-sources day summary; the macro and micronutrient sums come from the
/// app's own entries, so food logged by other apps counts up top but not
/// in the breakdown.
struct DayNutritionView: View {
    let model: TodayModel
    /// Calories available to eat that day and stay on the goal
    /// (`CalorieBudget.Plan.dailyBudget`). nil hides the row (no goal set).
    ///
    /// Past days used to be excluded here because the budget was anchored
    /// to TODAY and would have misled. It isn't any more: a completed day
    /// is built from the burn and target snapshotted when it happened, so
    /// the budget it shows is the one it actually had (2026-07-30).
    var dailyBudget: Double? = nil
    /// The deficit the day was aiming for — shown beside the net so the
    /// day's result has something to be measured against.
    var deficitGoal: Double? = nil
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnitRaw = SharedStore.unitAutomatic
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var waterUnit: WaterUnit { WaterUnit.resolve(waterUnitRaw) }
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }
    /// Differentiate Without Color: the remaining/sodium status hues
    /// gain a glyph twin (see BrandColors.sodiumStatusSymbol).
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var totals: NutrientValues { model.foodLog.totalNutrients }

    /// Green once the day has banked its goal, orange when it went the
    /// wrong way, plain while it's still short — a deficit that hasn't
    /// reached the target isn't a success to paint green, and it isn't a
    /// failure either.
    private var netTint: Color {
        let deficit = model.deficitKcal
        if deficit < 0 { return .orange }
        guard let deficitGoal, deficitGoal > 0 else { return .green }
        return deficit >= deficitGoal ? .green : .primary
    }

    /// The colors above are the only signal otherwise (the sodium row's
    /// rule — status must never be color-only).
    private var netStatusLabel: String {
        let deficit = model.deficitKcal
        if deficit < 0 { return "surplus" }
        guard let deficitGoal, deficitGoal > 0 else { return "deficit" }
        return deficit >= deficitGoal ? "goal met" : "short of goal"
    }

    var body: some View {
        List {
            summarySection
            if model.foodLog.isEmpty {
                // 1,800 kcal up top with "nothing logged" below read as
                // a bug — say where the calories came from.
                Text(model.summary.intakeKcal > 0
                    ? "Nothing logged in Onigiri — the calories above include other apps' entries."
                    : (model.isToday
                        ? "Nothing logged — log a meal to see its nutrients here."
                        : "Nothing was logged this day."))
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
                } footer: {
                    Text("Breakdown covers Onigiri entries only; the totals above include every app's Health data.")
                }
            }
        }
        .readableContentWidth(groupedBackground: true)
        .navigationTitle("Details")
    }

    private var dayLabel: String {
        if model.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day())
    }

    private var summarySection: some View {
        Section(dayLabel) {
            // The day's allowance to stay on the goal, up top. Budget and
            // remaining are present only for today with a goal (the caller
            // gates dailyBudget).
            if let dailyBudget {
                iconRow("Calorie budget", icon: { Image(systemName: "target").foregroundStyle(Color.riceToast) }) {
                    Text("\(dailyBudget, format: .number.precision(.fractionLength(0))) kcal")
                        .monospacedDigit()
                }
            }
            // The same icon this number wears on Today.
            iconRow("Calories logged", icon: { FoodIconView(raw: foodIcon) }) {
                Text("\(model.summary.intakeKcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            // Budget minus what's logged — the Today headline's "kcal
            // left", right under the two numbers it's from, tinted
            // green/amber/orange as it nears and passes the budget.
            if let dailyBudget {
                let remaining = dailyBudget - model.summary.intakeKcal
                iconRow("Calories remaining", icon: { Image(systemName: "chart.pie.fill").foregroundStyle(Color.remainingStatus(kcal: remaining)) }) {
                    HStack(spacing: 4) {
                        Text("\(remaining, format: .number.precision(.fractionLength(0))) kcal")
                            .foregroundStyle(Color.remainingStatus(kcal: remaining))
                            .monospacedDigit()
                            .accessibilityValue(Color.remainingStatusLabel(kcal: remaining) ?? "")
                        if differentiateWithoutColor,
                           let symbol = Color.remainingStatusSymbol(kcal: remaining) {
                            Image(systemName: symbol)
                                .font(.caption)
                                .foregroundStyle(Color.remainingStatus(kcal: remaining))
                                .accessibilityHidden(true)
                        }
                    }
                }
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
            // deficit (good), negative a surplus. "Net", not "Deficit" —
            // a row labeled Deficit reading "surplus" flipped signs on
            // the reader. The ± glyph says "signed balance".
            // Banked over goal, on ONE line in the sodium/water grammar —
            // "1,517 / 633" says on-track at a glance, where two separate
            // rows made the reader do the comparison (the user,
            // 2026-07-30). A surplus drops the goal: you aren't partway to
            // a deficit, you're the wrong side of zero, and "-27 / 633"
            // reads like arithmetic nobody asked for.
            iconRow("Net", icon: { Image(systemName: "plusminus").foregroundStyle(netTint) }) {
                let deficit = model.deficitKcal
                Group {
                    if deficit < 0 {
                        Text("\(-deficit, format: .number.precision(.fractionLength(0))) kcal surplus")
                    } else if let deficitGoal, deficitGoal > 0 {
                        Text("\(deficit, format: .number.precision(.fractionLength(0))) / \(deficitGoal, format: .number.precision(.fractionLength(0))) kcal deficit")
                    } else {
                        Text("\(deficit, format: .number.precision(.fractionLength(0))) kcal deficit")
                    }
                }
                .foregroundStyle(netTint)
                .monospacedDigit()
                .accessibilityValue(netStatusLabel)
            }
            // Both rows carry a VoiceOver twin of their status colors —
            // near/over limit and goal-met are otherwise color-only.
            iconRow(sodiumUnit.nutrientName, icon: { Text("🧂") }) {
                HStack(spacing: 4) {
                    // Status colors keep judging canonical mg.
                    Text("\(sodiumUnit.value(fromMg: model.summary.sodiumMg)) / \(sodiumUnit.text(fromMg: sodiumLimitMg))")
                        .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                        .monospacedDigit()
                        .accessibilityValue(Color.sodiumStatusLabel(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg) ?? "")
                    if differentiateWithoutColor,
                       let symbol = Color.sodiumStatusSymbol(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg) {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(Color.sodiumStatus(mg: model.summary.sodiumMg, limitMg: sodiumLimitMg))
                            .accessibilityHidden(true)
                    }
                }
            }
            iconRow("Water", icon: { WaterIconView(raw: waterIcon) }) {
                Text("\(waterUnit.value(fromOz: model.summary.waterOz)) / \(waterUnit.text(fromOz: waterGoalOz))")
                    .foregroundStyle(model.summary.waterOz >= waterGoalOz ? Color.green : Color.secondary)
                    .monospacedDigit()
                    .accessibilityValue(model.summary.waterOz >= waterGoalOz ? "goal met" : "")
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
