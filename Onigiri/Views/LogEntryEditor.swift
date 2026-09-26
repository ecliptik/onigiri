import SwiftUI
import OnigiriKit

/// Correcting a read before it is logged (`plans/PLAN-multi-item-import.md`).
///
/// Pushed from the confirm's item row, in the same stack the confirm
/// lives in, and it edits the entry IN PLACE through a binding: there is
/// no Save here, because nothing has been written yet — the confirm's own
/// Cancel still abandons the whole entry and its Save/Log are still the
/// only things that commit. A second Save/Cancel pair on this screen
/// would be asking twice about one decision.
///
/// It exists because a read can be WRONG in ways the receipt can only
/// report: a screenshot of a restaurant's nutrition panel named the item
/// after the topping it was configured with, filed 1 g of trans fat the
/// page printed as 0, and dropped the saturated fat entirely (the user,
/// 2026-09-20). In the app a single food goes to the full food form, so
/// this is mostly for the rows of a menu — but the SHARE EXTENSION has
/// no form at all, and before this its only choices were to accept the
/// numbers or lose the read. Compiled into both for that reason
/// (project.yml), and it uses nothing from `Style.swift`, which the
/// extension does not carry.
///
/// Every field can also be BLANK, which is its own answer: a nutrient
/// nobody published is nil, not zero, and clearing a field puts it back
/// to "not stated" rather than logging a zero.
struct LogEntryEditor: View {
    @Binding var label: ParsedLabel

    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults)
    private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }

    /// Macros open, micros shut — the opposite of the food form, where
    /// everything starts collapsed to keep Save in reach. Nothing is
    /// committed from this screen, and the row somebody came here to fix
    /// is nearly always a macro.
    @State private var macrosExpanded = true
    @State private var mineralsExpanded = false
    @State private var vitaminsExpanded = false
    @FocusState private var numberFieldFocused: Bool
    /// The serving the entry's numbers describe, so a retyped serving can
    /// say what it comes to and offer to rescale — the food form's rule
    /// (`ServingRescale`, 2026-09-25). Anchored on first appearance and
    /// whenever calories are set.
    @State private var servingBasis: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Name", text: nameText)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
                LabeledContent("Serving") {
                    TextField("1 serving", text: servingText)
                        .multilineTextAlignment(.trailing)
                }
                if let basis = servingBasis, let kcal = label.kcal,
                   let factor = ServingRescale.factor(from: basis, to: label.servingDescription ?? "") {
                    rescaleRow(factor: factor, kcal: kcal, basis: basis)
                }
                numberRow("Calories", value: number(\.kcal, clearing: .energy))
            } footer: {
                if label.aiGenerated {
                    // The estimate mark stays with the numbers, not with
                    // the fact that they were typed over: correcting one
                    // figure doesn't make a model's other figures
                    // measurements.
                    Text("These numbers were estimated. Anything you change here is used as you type it.")
                }
            }

            Section {
                DisclosureGroup(isExpanded: $macrosExpanded) {
                    // Nutrition-label order, matching the food form and
                    // the panel being copied.
                    numberRow("Fat (g)", value: number(\.nutrients.fatG, clearing: .fat))
                    numberRow("Saturated fat (g)",
                              value: number(\.nutrients.saturatedFatG, clearing: .saturatedFat))
                    numberRow("Trans fat (g)",
                              value: number(\.nutrients.transFatG, clearing: .transFat))
                    numberRow("Polyunsaturated fat (g)", value: number(\.nutrients.polyunsaturatedFatG))
                    numberRow("Monounsaturated fat (g)", value: number(\.nutrients.monounsaturatedFatG))
                    numberRow("Cholesterol (mg)",
                              value: number(\.nutrients.cholesterolMg, clearing: .cholesterol))
                    // Salt mode edits grams-of-salt (the EU label's own
                    // framing) through a converted binding; the stored
                    // field stays sodium in mg, like every other readout
                    // in the app.
                    numberRow("\(sodiumUnit.nutrientName) (\(sodiumUnit.symbol))", value: sodiumEntry)
                    numberRow("Carbs (g)", value: number(\.nutrients.carbsG, clearing: .carbs))
                    numberRow("Fiber (g)", value: number(\.nutrients.fiberG, clearing: .fiber))
                    numberRow("Sugar (g)", value: number(\.nutrients.sugarG, clearing: .sugar))
                    numberRow("Protein (g)", value: number(\.nutrients.proteinG, clearing: .protein))
                    numberRow("Caffeine (mg)", value: number(\.nutrients.caffeineMg))
                } label: {
                    groupLabel("Macronutrients", filled: macroFieldCount)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $mineralsExpanded) {
                    microRows(Micronutrient.minerals)
                } label: {
                    groupLabel("Minerals", filled: microFieldCount(Micronutrient.minerals))
                }
            }

            Section {
                DisclosureGroup(isExpanded: $vitaminsExpanded) {
                    microRows(Micronutrient.vitamins)
                } label: {
                    groupLabel("Vitamins", filled: microFieldCount(Micronutrient.vitamins))
                }
            }
        }
        .navigationTitle("Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if servingBasis == nil { servingBasis = label.servingDescription ?? "" }
        }
        .onChange(of: label.kcal) { _, _ in servingBasis = label.servingDescription ?? "" }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // Decimal pads have no return key; surface a Done while
            // editing, the same way the food form does (keyboard
            // accessory placement is unreliable on iOS 26). Plain and
            // unstyled — a custom `buttonStyle` on a bar item is the
            // 2026-08-30 clipped-circle landmine.
            if numberFieldFocused {
                ToolbarItem(placement: .principal) {
                    Button("Done") { numberFieldFocused = false }
                }
            }
        }
    }

    // MARK: Rows

    private func numberRow(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            // "—" rather than "0": a nutrient nobody published has no
            // value, and a zero placeholder invites logging one.
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($numberFieldFocused)
        }
    }

    private func microRows(_ group: [Micronutrient]) -> some View {
        ForEach(group) { micro in
            numberRow("\(micro.displayName) (\(micro.unit.symbol))", value: microValue(micro))
        }
    }

    private func groupLabel(_ title: String, filled: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if filled > 0 {
                Text("\(filled) filled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Bindings

    private var nameText: Binding<String> {
        Binding(
            get: { label.name ?? "" },
            set: { typed in
                label.name = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : typed
            }
        )
    }

    /// The food form's rescale row, for this screen's entry.
    private func rescaleRow(factor: Double, kcal: Double, basis: String) -> some View {
        let target = ServingRescale.completed(label.servingDescription ?? "", after: basis)
        return Button {
            label.kcal = kcal * factor
            label.sodiumMg = label.sodiumMg.map { $0 * factor }
            label.nutrients = label.nutrients.scaled(by: factor)
            label.servingDescription = target
            servingBasis = target
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update nutrition for \(target)")
                    Text("\(kcal.formatted(.number.precision(.fractionLength(0...1)))) kcal is for \(basis)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\((kcal * factor).formatted(.number.precision(.fractionLength(0)))) kcal")
                    .monospacedDigit()
            }
        }
        .accessibilityHint("Multiplies every nutrient by the change in serving")
        .accessibilityIdentifier("servingRescale")
    }

    private var servingText: Binding<String> {
        Binding(
            get: { label.servingDescription ?? "" },
            set: { raw in
                // A measure, never an emoji — the suggestion bar offers
                // 💯 for "100" (`EmojiText`).
                let typed = EmojiText.stripped(raw)
                label.servingDescription = typed
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : typed
            }
        )
    }

    /// A value the user typed is no longer a value Onigiri READ, so the
    /// plausibility finding that judged the read goes with it — both the
    /// ⚠️ beside the row on the confirm and, for a figure the gate threw
    /// away, the "was left out" note. Leaving it would mark a number
    /// nobody parsed as suspect, and go on warning about a gap that has
    /// just been filled.
    private func number(
        _ path: WritableKeyPath<ParsedLabel, Double?>,
        clearing field: NutritionPlausibility.Field? = nil
    ) -> Binding<Double?> {
        Binding(
            get: { label[keyPath: path] },
            set: { newValue in
                label[keyPath: path] = newValue
                if let field { label.warnings.removeAll { $0.field == field } }
            }
        )
    }

    private var sodiumEntry: Binding<Double?> {
        Binding(
            get: { label.sodiumMg.map { (sodiumUnit.fromMg($0) * 100).rounded() / 100 } },
            set: { newValue in
                label.sodiumMg = newValue.map(sodiumUnit.toMg)
                label.warnings.removeAll { $0.field == .sodium }
            }
        )
    }

    private func microValue(_ micro: Micronutrient) -> Binding<Double?> {
        Binding(
            get: { label.nutrients.micros[micro.rawValue] },
            set: { label.nutrients.micros[micro.rawValue] = $0 }
        )
    }

    // MARK: Counts

    private var macroFieldCount: Int {
        let n = label.nutrients
        return [n.fatG, n.saturatedFatG, n.transFatG, n.polyunsaturatedFatG,
                n.monounsaturatedFatG, n.cholesterolMg, label.sodiumMg, n.carbsG,
                n.fiberG, n.sugarG, n.proteinG, n.caffeineMg]
            .count { ($0 ?? 0) > 0 }
    }

    private func microFieldCount(_ group: [Micronutrient]) -> Int {
        group.count { (label.nutrients.micros[$0.rawValue] ?? 0) > 0 }
    }
}
