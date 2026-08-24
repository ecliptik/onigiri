import SwiftUI
import OnigiriKit

/// The last step: what is about to be logged, which meal it belongs to,
/// and how many. Deliberately not the app's whole food form — picking a
/// row off a list is a moment, not a workspace. The committing action is
/// NOT here; it sits in the navigation bar beside Cancel, where the app
/// puts Save.
///
/// Compiled into the app AND the share extension
/// (`plans/PLAN-multi-item-import.md`), because both reach it through
/// `MenuPickerFlow` and a receipt that differs by process is a receipt
/// nobody can check. It began as the extension's `ShareLogSheet`.
///
/// The "Also logged" section is the reason a quick confirm is acceptable
/// at all: this sheet showed the name, the calories and the serving while
/// `logFood` wrote sodium and five macros beside them, and a shared page
/// logged 810,400 mg of sodium behind it — the only place that number
/// ever appeared was the log itself (2026-08-16,
/// `plans/PLAN-nutrition-plausibility.md`). Never trim it back to the
/// headline figures.
struct LogConfirmSheet: View {
    let label: ParsedLabel
    @Binding var category: FoodCategory
    @Binding var quantity: Double
    /// The app's optional library save. `nil` where the host saves
    /// unconditionally and there is nothing to ask — the share
    /// extension, which has no other way to keep the dish.
    ///
    /// The app's rule is the opposite and the user wrote it: saving to
    /// the library is the option, not the price of admission
    /// (`QuickLogSheet`, `purpose: .logging`). So the toggle exists, and
    /// it starts OFF.
    var saveToLibrary: Binding<Bool>?
    let logging: Bool
    /// Why the last attempt didn't take. Shown HERE rather than as a
    /// toast: this sheet is the top of the stack, and a toast raised by
    /// the host underneath it would be invisible at the moment it
    /// mattered.
    var failure: String?

    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults)
    private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }

    /// The gate's verdict on one row, when it had one to give
    /// (`NutritionPlausibility`). Suspect values are shown and marked;
    /// impossible ones are already gone, and are named in the footer.
    private func suspect(_ id: String) -> NutritionPlausibility.Finding? {
        label.warnings.first { $0.severity == .suspect && $0.field.rawValue == id }
    }

    /// The findings that have no row to sit beside: what was removed,
    /// and an energy figure its own macros contradict.
    private var notes: [String] {
        label.warnings.compactMap { finding in
            switch finding.severity {
            case .dropped:
                "\(finding.field.displayName) was left out — \(finding.reason)"
            case .suspect:
                finding.field == .energy ? finding.reason : nil
            }
        }
    }

    /// Everything the Log button is about to write, scaled to the
    /// portion — the RECEIPT for it.
    ///
    /// This sheet showed the name, the calories and the serving while
    /// `logFood` wrote sodium and five macros beside them, so a figure
    /// read wrongly off a page could not be caught before it was in
    /// Health: a shared product page logged 810,400 mg of sodium and the
    /// only place that number ever appeared was the log itself
    /// (2026-08-16, `plans/PLAN-nutrition-plausibility.md`). One button,
    /// one write, one list — a value not shown here is a value nobody
    /// agreed to.
    private var written: [(id: String, name: String, amount: String)] {
        var rows: [(String, String, String)] = []
        func add(_ id: String, _ name: String, _ value: Double?, _ unit: String,
                 digits: ClosedRange<Int> = 0...1) {
            guard let value else { return }
            rows.append((id, name,
                "\(value.formatted(.number.precision(.fractionLength(digits)))) \(unit)"))
        }
        if let sodiumMg = label.sodiumMg {
            let digits = sodiumUnit.fractionDigits
            add("sodium", sodiumUnit.nutrientName, sodiumUnit.fromMg(sodiumMg * quantity),
                sodiumUnit.symbol, digits: digits...digits)
        }
        let n = label.nutrients.scaled(by: quantity)
        add("fat", "Fat", n.fatG, "g")
        add("saturatedFat", "Saturated fat", n.saturatedFatG, "g")
        add("transFat", "Trans fat", n.transFatG, "g")
        add("polyunsaturatedFat", "Polyunsaturated fat", n.polyunsaturatedFatG, "g")
        add("monounsaturatedFat", "Monounsaturated fat", n.monounsaturatedFatG, "g")
        add("cholesterol", "Cholesterol", n.cholesterolMg, "mg")
        add("carbs", "Carbohydrates", n.carbsG, "g")
        add("fiber", "Fiber", n.fiberG, "g")
        add("sugar", "Sugar", n.sugarG, "g")
        add("protein", "Protein", n.proteinG, "g")
        add("caffeine", "Caffeine", n.caffeineMg, "mg")
        for micro in Micronutrient.allCases {
            add(micro.rawValue, micro.displayName, n[micro], micro.unit.symbol)
        }
        return rows
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(label.name ?? "Menu item") {
                    if let kcal = label.kcal {
                        Text("\((kcal * quantity).formatted(.number.precision(.fractionLength(0)))) kcal")
                            .monospacedDigit()
                    }
                }
                if let serving = label.servingDescription {
                    LabeledContent("Serving", value: serving)
                }
                if label.aiGenerated {
                    Label("Estimated — review before logging", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if written.isEmpty {
                    Text("Calories only — nothing else was published for this item.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(written, id: \.id) { row in
                        LabeledContent(row.name) {
                            HStack(spacing: 6) {
                                if suspect(row.id) != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                                Text(row.amount).monospacedDigit()
                            }
                        }
                        if let reason = suspect(row.id)?.reason {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Also logged")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everything Onigiri will write to Health, for this portion.")
                    // What was REMOVED has to be said too: a figure
                    // silently dropped and a figure never read look
                    // identical here, and only one of them means the
                    // page said something Onigiri refused to believe.
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                    }
                }
            }
            Section {
                Picker("Meal", selection: $category) {
                    ForEach(FoodCategory.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
                }
                Stepper(
                    "Quantity \(quantity.formatted(.number.precision(.fractionLength(0...2))))",
                    value: $quantity, in: 0.25...20, step: 0.25)
            }
            if let saveToLibrary {
                Section {
                    Toggle("Save to Food Library", isOn: saveToLibrary)
                } footer: {
                    // What NOT saving costs, so the default reads as a
                    // choice rather than an oversight: the log itself is
                    // never at stake, and a logged food comes back through
                    // the Log sheet's history rows either way.
                    Text("Saved foods are one tap next time. Either way this log is kept.")
                }
            }
            if logging {
                Section {
                    HStack { ProgressView(); Text("Logging…") }
                }
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .disabled(logging)
    }
}
