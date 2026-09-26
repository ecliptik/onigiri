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
/// The "Nutrition" section (named "Also logged" until 2026-08-29, when
/// Save stopped making that name true for every row shown here) is the
/// reason a quick confirm is acceptable at all: this sheet showed the
/// name, the calories and the serving while `logFood` wrote sodium and
/// five macros beside them, and a shared page logged 810,400 mg of
/// sodium behind it — the only place that number ever appeared was the
/// log itself (2026-08-16, `plans/PLAN-nutrition-plausibility.md`).
/// Never trim it back to the headline figures.
struct LogConfirmSheet: View {
    /// A BINDING since 2026-09-20: the item row pushes `LogEntryEditor`,
    /// which corrects the read in place. The sheet stays a receipt —
    /// nothing here is committed until Save or Log — but a receipt you
    /// cannot correct was a dead end in the share extension, which has
    /// no food form to fall back to.
    @Binding var label: ParsedLabel
    @Binding var category: FoodCategory
    @Binding var quantity: Double
    /// The serving the numbers were read against — handed to the editor,
    /// owned by the flow (`LogEntryEditor.servingBasis`).
    @Binding var servingBasis: String
    /// Which of the confirm's three actions is running, if either — `nil`
    /// while idle. They share this one flag because only one can ever be
    /// in flight (every button disables together), and the reader only
    /// needs to know which verb to show.
    ///
    /// There is no library toggle any more. Whether a log also saves was
    /// the app's toggle (default off) and the extension's silent rule
    /// (always) — two answers to one question, neither on screen as a
    /// choice where it was made. It is a BUTTON now, Save & Log, in every
    /// host (the user, 2026-09-24).
    enum Busy { case logging, saving, savingAndLogging }
    var busy: Busy?
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
                // Right under the kcal it scales, so the total stays in
                // view while adjusting — below a long AI serving it sat
                // off screen (2026-09-22, the portion sheet's fix).
                Stepper(
                    "Quantity \(quantity.formatted(.number.precision(.fractionLength(0...2))))",
                    value: $quantity, in: 0.25...20, step: 0.25)
                if let serving = label.servingDescription {
                    LabeledContent("Serving", value: serving)
                }
                // A NAMED control, not a tappable row with a caption
                // under it explaining that it is tappable (the user,
                // 2026-09-21: "edit isn't obvious ... could we add an
                // explicit Edit button"). The item row itself pushed the
                // editor for a day and the hint below it had to say so,
                // which is the shape of an affordance that isn't one.
                // ONE chevron in this card on purpose: two would read as
                // two destinations.
                NavigationLink {
                    LogEntryEditor(label: $label, servingBasis: $servingBasis)
                } label: {
                    Label("Edit Item", systemImage: "square.and.pencil")
                }
                if label.aiGenerated {
                    Label("Estimated — review before logging", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            // ABOVE the receipt: the controls that decide the log sat
            // under a list long enough to push them off the screen (the
            // user, 2026-08-24). The quantity now sits in the card above,
            // beside the kcal it scales.
            Section {
                Picker("Meal", selection: $category) {
                    ForEach(FoodCategory.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
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
                Text("Nutrition")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    // Not "will write to Health": Save never does, and
                    // only Save & Log reaches both — a claim this footer
                    // can't make for every button on the screen
                    // (2026-08-29). Not "found": a figure corrected in
                    // the editor was typed, not read, and this list has
                    // to stay true of both.
                    Text("Everything on this entry, for this portion.")
                    // What was REMOVED has to be said too: a figure
                    // silently dropped and a figure never read look
                    // identical here, and only one of them means the
                    // page said something Onigiri refused to believe.
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                    }
                }
            }
            if let busy {
                Section {
                    HStack { ProgressView(); Text(busyText(busy)) }
                }
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .disabled(busy != nil)
    }

    private func busyText(_ busy: Busy) -> String {
        switch busy {
        case .logging: "Logging…"
        case .saving: "Saving…"
        case .savingAndLogging: "Saving and logging…"
        }
    }
}
