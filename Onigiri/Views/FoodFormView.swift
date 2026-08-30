import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts. The one surface every new food passes through; its
/// confirm pair follows the route that opened it (see `Purpose`).
struct FoodFormView: View {
    /// Which route opened the form. It decides the confirm PAIR and
    /// nothing else — same fields, same scanner, same everything.
    ///
    /// The Foods tab and the Log sheet answer different questions (the
    /// same reason the Log sheet's opening scope is deliberately not
    /// the Foods tab's setting). You reach this form from Today → Log
    /// because you are logging something, and the old pair offered no
    /// way to log a one-off — a restaurant plate, a friend's cooking —
    /// without permanently enlarging the library (the user,
    /// 2026-08-07).
    enum Purpose {
        /// Foods tab: Save (library only) / Save & Log.
        case library
        /// Log sheet: Log (no library row at all) / Log & Save.
        case logging
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?
    /// Open the barcode scanner immediately (quick-action entry point).
    var startScanning = false
    /// Prefill from a scanned/searched product (new-food log flow).
    var prefill: ScannedProduct?
    /// Provenance for a prefill that arrived from an AI estimate
    /// (ProductPrefill.provenance) — seeds the lookup caption on open.
    var prefillMessage: String? = nil
    /// Timestamp for the entry the Log action writes (backfill support).
    var logDate: Date = .now
    /// Called after the Log action completes, so the presenter can dismiss too.
    var onLogged: (() -> Void)?
    /// Which confirm pair to offer. Defaulted, so only the Log sheet
    /// has to say anything.
    var purpose: Purpose = .library

    @State private var name = ""
    @State private var kcal: Double?
    @State private var sodiumMg: Double?
    /// What the plausibility gate said about the prefill this form
    /// opened on — empty for anything typed by hand.
    @State private var warnings: [NutritionPlausibility.Finding] = []
    /// A database row that carries the same name as an ESTIMATE this
    /// form was prefilled with, when one exists and online lookups are
    /// on. Offered, never applied on its own (`PublishedLookup`).
    @State private var publishedOffer: ScannedProduct?
    /// Kept so a second prefill cancels the first's lookup — an offer
    /// arriving for the food you already replaced is worse than none.
    @State private var offerTask: Task<Void, Never>?
    /// Sodium's display unit; the field state above stays canonical mg.
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }
    /// Salt mode shows 2 decimals (0.75 g salt = 300 mg — one decimal
    /// would drop real label precision); mg passes through untouched.
    private var sodiumEntryBinding: Binding<Double?> {
        Binding(
            get: { sodiumMg.map { (sodiumUnit.fromMg($0) * 100).rounded() / 100 } },
            set: { sodiumMg = $0.map(sodiumUnit.toMg) }
        )
    }
    @State private var serving = ""
    @State private var barcode: String?
    @State private var fatG: Double?
    @State private var saturatedFatG: Double?
    @State private var transFatG: Double?
    @State private var polyunsaturatedFatG: Double?
    @State private var monounsaturatedFatG: Double?
    @State private var cholesterolMg: Double?
    @State private var carbsG: Double?
    @State private var proteinG: Double?
    @State private var fiberG: Double?
    @State private var sugarG: Double?
    @State private var caffeineMg: Double?
    @State private var micros: [String: Double] = [:]
    @State private var microsExpanded = false
    @State private var mineralsExpanded = false
    @State private var nutrientsExpanded = false
    @State private var category: String?
    @State private var isFavorite = false

    /// The form's ONE presentation slot: chained .sheet modifiers on a
    /// view compete (the CLAUDE.md landmine — FoodsView/QuickLogSheet
    /// already got this consolidation); a single .sheet(item:) can't.
    private enum ActiveSheet: Identifiable {
        case scanner(notice: String?)
        case portion(PortionTarget)
        var id: String {
            switch self {
            case .scanner(let notice): "scanner-\(notice ?? "")"
            case .portion(let target): "portion-\(target.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    /// What's typed into the entry door's "Describe food or meal" field —
    /// drives BOTH `AIEstimateSection` and `OnlineResultsSection` now
    /// (2026-08-29). The bottom `.searchable` field this form used to
    /// carry for OpenFoodFacts/USDA is retired along with it — this form
    /// has no local library to search, so once online moved here there
    /// was nothing left for a second field to do.
    @State private var describeQuery = ""
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    /// AI-estimate provenance — set by any AI prefill/apply, persisted
    /// on the food, shown as ✨ in library rows.
    @State private var aiGenerated = false
    /// onDismiss fires after activeSheet is already nil — this marker
    /// says the closed sheet was the portion sheet, so the "saved but
    /// not logged" toast only follows an actual portion cancel.
    @State private var portionSheetWasUp = false
    @State private var portionDidLog = false
    /// Did the action that opened the portion sheet already persist the
    /// food? It decides what a CANCELLED portion means — see
    /// `sheetDidDismiss`.
    @State private var savedBeforePortion = false
    /// Cancel/drag with typed data confirms first — twelve typed
    /// nutrient fields used to vanish on a stray swipe.
    @State private var confirmDiscard = false
    @State private var initialSnapshot: FieldsSnapshot?
    /// Duplicate-food guard: a prefill whose name is already in the
    /// library offers editing that food instead of minting a twin.
    @State private var duplicateMatch: Food?
    /// A new food inserted by the Log action, so a second save updates it
    /// instead of inserting a duplicate.
    @State private var createdFood: Food?
    @FocusState private var numberFieldFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kcal != nil
    }

    /// Everything the form edits, for the dirty check.
    private struct FieldsSnapshot: Equatable {
        var name: String
        var kcal: Double?
        var sodiumMg: Double?
        var serving: String
        var barcode: String?
        var nutrients: NutrientValues
        var category: String?
        var isFavorite: Bool
    }

    private var currentSnapshot: FieldsSnapshot {
        FieldsSnapshot(
            name: name, kcal: kcal, sodiumMg: sodiumMg, serving: serving,
            barcode: barcode, nutrients: formNutrients,
            category: category, isFavorite: isFavorite
        )
    }

    private var isDirty: Bool {
        initialSnapshot.map { $0 != currentSnapshot } ?? false
    }

    /// Blank while the two-button PAIR is on screen.
    ///
    /// A new food shows Cancel + two confirm buttons, and an inline
    /// title between them left "Cancel  New Food  Log  Log & Save"
    /// reading as crowded (the user, 2026-08-08). Measured, it never
    /// truncates — even iPhone SE at XXL text fits both — but tight is
    /// still tight, and of the four things in that bar the title is the
    /// one the form's own fields already tell you. Editing keeps its
    /// title: one Save button leaves plenty of room.
    private var navigationTitleText: String {
        food == nil ? "" : "Edit Food"
    }

    /// What the screen IS, for VoiceOver, whether or not the bar shows
    /// it. Dropping the visible title took the announcement with it —
    /// the nav-bar title is what VoiceOver reads on presenting a sheet,
    /// so an untitled form opened straight onto a provenance caption or
    /// a text field with no statement of where you are.
    private var accessibilityTitle: String {
        food == nil && createdFood == nil ? "New Food" : "Edit Food"
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(navigationTitleText)
                .navigationBarTitleDisplayMode(.inline)
                // A heading with no visual weight. NOT `.hidden()` —
                // that removes it from the accessibility tree too,
                // which is the whole thing being preserved here;
                // zero opacity leaves it in. Top-aligned so it is the
                // first thing read, and hit-testing off so it can never
                // take a tap from the form beneath it.
                .overlay(alignment: .top) {
                    Text(accessibilityTitle)
                        .font(.caption)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityAddTraits(.isHeader)
                }
        }
        .toastHost()
    }

    /// The scanner, describe field and online search exist to FILL a
    /// blank form. A form opened FROM a search result (or editing a
    /// saved food) offering another search was a loop — they render
    /// only for a blank new food, the Foods-screen add path.
    private var isBlankNewFood: Bool {
        food == nil && prefill == nil && createdFood == nil
    }

    private var formContent: some View {
            Form {
                // The scanner leads the form as a labeled row (Micheal's
                // pick — the toolbar icon crowded the Save cluster);
                // lookup status lands right beneath it. The search field
                // lives at the bottom, system placement.
                // The shared scan door — identical on Foods, the Log
                // sheet, and here (PLAN-entry-doors). The scan door
                // shows this form's lookup provenance in its caption.
                if isBlankNewFood {
                    EntryDoorsSection(
                        scanBusy: isLookingUp,
                        scanCaption: lookupMessage,
                        describeQuery: $describeQuery,
                        onScan: { activeSheet = .scanner(notice: nil) },
                        onDescribeSubmit: { Task { await onlineSearch.search(describeQuery) } }
                    )
                    // The describe field's own results, right under
                    // where it's typed (2026-08-29) — AI → online, the
                    // order the field's own doc comment and the rest of
                    // the app already use. Picking either applies the
                    // catch to the fields below, with the provenance in
                    // the scan-door caption slot.
                    if !describeQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        if FoodIntelligence.isAvailable {
                            AIEstimateSection(query: describeQuery) { product in
                                apply(product)
                                lookupMessage = product.aiEngine?.estimateCaption
                                describeQuery = ""
                            }
                        }
                        // Moved from the retired bottom search field
                        // (2026-08-29) — same section, same behavior,
                        // just driven by the describe field now.
                        if SharedStore.onlineLookups {
                            OnlineResultsSection(query: describeQuery, search: onlineSearch, onPick: { product in
                                apply(product)
                                describeQuery = ""
                                onlineSearch.clear()
                            }, onAddManually: { pickedName in
                                name = pickedName
                                describeQuery = ""
                                onlineSearch.clear()
                            })
                        }
                    }
                } else if let lookupMessage {
                    // Prefilled opens hide the doors (the form isn't
                    // blank), so provenance that traveled in with the
                    // prefill — Foods' describe door, most importantly —
                    // needs its own row or "review before saving" is
                    // silently lost at the sheet boundary.
                    Section {
                        Text(lookupMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Name", text: $name)
                        // The siblings get spoken labels from their
                        // LabeledContent; this placeholder rides as the
                        // VALUE and vanishes once text is typed, leaving
                        // the field nameless to VoiceOver.
                        .accessibilityLabel("Name")
                    LabeledContent("Calories (kcal)") {
                        TextField("0", value: $kcal, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($numberFieldFocused)
                    }
                    LabeledContent("Serving") {
                        TextField("e.g. 1 cup, 8 oz", text: $serving)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Published figures for a food the model only ESTIMATED
                // — offered, never substituted (`PublishedLookup`).
                // Accuracy comes from data: the evals' worst sodium miss
                // is a Big Mac at 2,400 mg where McDonald's publishes
                // ~1,010, and no prompt fixes a number the model does
                // not know.
                if let offer = publishedOffer {
                    Section {
                        Button {
                            applyPublished(offer)
                        } label: {
                            publishedRow(offer)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Published values")
                    } footer: {
                        // The SERVING is part of the offer and has to be
                        // read: a per-100 g row is a different portion
                        // from "1 Big Mac", and swapping one for the
                        // other silently would be its own bug.
                        Text("A database has this name. Tap to use its figures and serving instead of the estimate.")
                    }
                }

                Section {
                    Picker("Category", selection: $category) {
                        Text("None").tag(String?.none)
                        ForEach(FoodCategory.allCases) { option in
                            Text(option.rawValue).tag(String?.some(option.rawValue))
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                }

                // Both nutrient groups start collapsed so Save stays
                // in reach; the filled counts show a scan brought data in.
                // Nutrition-label order, matching the label being copied.
                // Trans fat is app-only: Apple Health has no type for it.
                Section {
                    DisclosureGroup(isExpanded: $nutrientsExpanded) {
                        nutrientRow("Fat (g)", value: $fatG)
                        nutrientRow("Saturated fat (g)", value: $saturatedFatG)
                        nutrientRow("Trans fat (g)", value: $transFatG)
                        nutrientRow("Polyunsaturated fat (g)", value: $polyunsaturatedFatG)
                        nutrientRow("Monounsaturated fat (g)", value: $monounsaturatedFatG)
                        nutrientRow("Cholesterol (mg)", value: $cholesterolMg)
                        // Salt mode edits grams-of-salt (EU label
                        // framing) through a converted binding — the
                        // stored field stays sodium mg.
                        nutrientRow(
                            sodiumUnit == .milligrams ? "Sodium (mg)" : "Salt (g)",
                            value: sodiumEntryBinding
                        )
                        nutrientRow("Carbs (g)", value: $carbsG)
                        nutrientRow("Fiber (g)", value: $fiberG)
                        nutrientRow("Sugar (g)", value: $sugarG)
                        nutrientRow("Protein (g)", value: $proteinG)
                        nutrientRow("Caffeine (mg)", value: $caffeineMg)
                    } label: {
                        // "Macronutrients", like the day detail and the
                        // tracked-metric picker — one taxonomy app-wide.
                        groupLabel("Macronutrients", filled: nutrientFieldCount)
                    }
                } footer: {
                    // What the plausibility gate made of the prefill. A
                    // blank field that was blanked ON PURPOSE has to say
                    // so — otherwise "no sodium was published" and
                    // "the sodium read was nonsense" look identical, and
                    // only one of them is worth checking the label for
                    // (`NutritionPlausibility`).
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(warnings, id: \.reason) { finding in
                                Label(caption(for: finding), systemImage: "exclamationmark.triangle")
                            }
                        }
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
                    DisclosureGroup(isExpanded: $microsExpanded) {
                        microRows(Micronutrient.vitamins)
                    } label: {
                        groupLabel("Vitamins", filled: microFieldCount(Micronutrient.vitamins))
                    }
                }

                // Where these numbers came from — the OFF product page
                // directly; FDC's site 404s deep item links (verified
                // live), so its link opens this food's name searched on
                // fdc.nal.usda.gov instead.
                if let provenanceLine {
                    Section {
                    } footer: {
                        Text(.init(provenanceLine))
                    }
                }
            }
            .compactSections()
            .riceCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            confirmDiscard = true
                        } else {
                            offerTask?.cancel()
                            // The inline database search dies with the
                            // form — clear() cancels its search/page
                            // tasks (audit, 2026-08-17; offerTask's
                            // here-not-onDisappear rule).
                            onlineSearch.clear()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                // New foods get a PAIR, and which pair follows the route
                // (Purpose): from the library you Save, optionally
                // logging too; from a logging flow you Log, optionally
                // saving too. Both pairs put the "…& …" combined action
                // second and emphasized, on ⇧⌘S; the plain one is ⌘S.
                // (Two toolbar buttons replaced the old post-save
                // "Log it?" alert — a whole modal for a yes/no.)
                ToolbarItemGroup(placement: .confirmationAction) {
                    if food == nil {
                        Button(purpose == .logging ? "Log" : "Save") {
                            if purpose == .logging { logOnly() } else { saveOnly() }
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSave)
                        Button(purpose == .logging ? "Log & Save" : "Save & Log") { saveAndLog() }
                            .fontWeight(.semibold)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .disabled(!canSave)
                    } else {
                        Button("Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!canSave)
                    }
                }
                // Decimal pads have no return key; surface a Done while
                // editing (keyboard-accessory placement is unreliable on
                // iOS 26). The sheet's Cancel/Save stay reachable regardless.
                if numberFieldFocused {
                    ToolbarItem(placement: .principal) {
                        Button {
                            numberFieldFocused = false
                        } label: {
                            Text("Done")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.onRicePaper)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.ricePaper)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Pre-filled values are usually replaced, not appended to:
            // select all on focus so typing overwrites. Async so the
            // selection lands after the cursor placement.
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )) { note in
                // The notification is app-wide: while one of this form's
                // own sheets is up (scanner, portion), its fields must
                // not inherit the select-all. The describe field is
                // exempt too — selecting-all an in-progress query on
                // refocus would surprise — matched by accessibility
                // identifier since it carries no active-search flag of
                // its own to gate on (the bottom search field this form
                // used to carry, and its own exemption, retired
                // 2026-08-29 along with it).
                guard activeSheet == nil,
                      let field = note.object as? UITextField,
                      field.accessibilityIdentifier != EntryDoorsSection.describeFieldAccessibilityID
                else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            // On a background layer: two .alert modifiers chained on the
            // same view compete, like the .sheet landmine.
            .background {
                Color.clear.alert(
                    "“\(duplicateMatch?.name ?? "")” is already in your Food Library",
                    isPresented: .init(
                        get: { duplicateMatch != nil },
                        set: { if !$0 { duplicateMatch = nil } }
                    ),
                    presenting: duplicateMatch
                ) { match in
                    Button("Edit Existing") { adopt(match) }
                    // Cancel role: dismissing the alert should mean the
                    // safe default (keep both foods), and the alert gets
                    // a bolded default button.
                    Button("Create New", role: .cancel) {}
                } message: { _ in
                    Text("Edit keeps your saved values and attaches this barcode; Create New makes a separate food.")
                }
            }
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) {
                    offerTask?.cancel()
                    onlineSearch.clear()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(isDirty)
            .sheet(item: $activeSheet, onDismiss: sheetDidDismiss) { sheet in
                switch sheet {
                case .scanner(let notice):
                    ScanSheet(onCode: { code in
                        Task { await lookup(code) }
                    }, onLabel: { parsed in
                        applyLabel(parsed)
                    }, onFood: { product in
                        // Identified from a photo of the food itself:
                        // estimates, not printed values — say so, in the
                        // same slot the other lookup notes use, naming
                        // the provider (BYO-AI can send the photo off
                        // device; "on-device" would be a lie there).
                        apply(product)
                        lookupMessage = product.aiEngine?.photoEstimateCaption
                    }, notice: notice)
                case .portion(let target):
                    PortionSheet(target: target) { quantity, category, _ in
                        portionDidLog = true
                        log(target, quantity: quantity, category: category)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                if let food {
                    loadFields(from: food)
                } else if let prefill {
                    apply(prefill)
                    if let prefillMessage { lookupMessage = prefillMessage }
                } else if startScanning {
                    activeSheet = .scanner(notice: nil)
                }
                // After the initial load: a pristine form (or an
                // untouched prefill) dismisses freely; anything typed
                // or scanned IN the form confirms first.
                initialSnapshot = currentSnapshot
            }
    }

    /// "Source:" for a food that carries an online identity — an fdc:
    /// code or a numeric barcode. Editable name feeds the FDC link, so
    /// it lives here, not in the shared results section.
    private var provenanceLine: String? {
        guard let barcode, !barcode.isEmpty else { return nil }
        if FoodDataCentralClient.fdcId(fromCode: barcode) != nil {
            let query = name.trimmingCharacters(in: .whitespaces)
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            guard !query.isEmpty else { return nil }
            return "Source: [USDA](https://fdc.nal.usda.gov/food-search/?query=\(query))"
        }
        guard barcode.allSatisfy(\.isNumber) else { return nil }
        return "Source: [OpenFoodFacts](https://world.openfoodfacts.org/product/\(barcode))"
    }


    /// Duplicate-food guard: fires only for NEW foods whose prefill is
    /// already in the library (Micheal's manual-entry-then-scan case).
    /// Barcode beats name — a product saved under a different name used
    /// to sail past and mint a twin. Manual typing is not guarded —
    /// that's deliberate.
    private func checkForDuplicate() {
        guard food == nil, createdFood == nil else { return }
        // On-demand fetch, not an @Query: the form doesn't render the
        // library, and the standing query kept every food materialized
        // and re-rendered the form on any library change.
        if let code = barcode, !code.isEmpty {
            var descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == code })
            descriptor.fetchLimit = 1
            if let match = ((try? context.fetch(descriptor)) ?? []).first {
                duplicateMatch = match
                return
            }
        }
        // Name matching is fuzzy (LibraryDuplicate) — not predicable.
        let all = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        duplicateMatch = all.first { LibraryDuplicate.nameMatches($0.name, name) }
    }

    /// "Edit Existing": the form becomes an editor for the matched food —
    /// library values win (the rescan quirk, deliberately), and the
    /// scanned barcode is attached so future scans take the fast path.
    private func adopt(_ match: Food) {
        let scannedBarcode = barcode
        loadFields(from: match)
        if barcode == nil || barcode?.isEmpty == true {
            barcode = scannedBarcode
        }
        createdFood = match
    }

    private func loadFields(from food: Food) {
        name = food.name
        kcal = food.kcal
        sodiumMg = food.sodiumMg
        serving = food.servingDescription
        barcode = food.barcode
        fatG = food.fatG
        saturatedFatG = food.saturatedFatG
        transFatG = food.transFatG
        polyunsaturatedFatG = food.polyunsaturatedFatG
        monounsaturatedFatG = food.monounsaturatedFatG
        cholesterolMg = food.cholesterolMg
        carbsG = food.carbsG
        proteinG = food.proteinG
        fiberG = food.fiberG
        sugarG = food.sugarG
        caffeineMg = food.caffeineMg
        micros = food.micros ?? [:]
        category = food.category
        isFavorite = food.isFavorite
        aiGenerated = food.aiGenerated
    }

    /// Zero is "nothing on the label", not data worth advertising —
    /// only positive values count as filled.
    private var nutrientFieldCount: Int {
        [fatG, saturatedFatG, transFatG, polyunsaturatedFatG, monounsaturatedFatG,
         cholesterolMg, sodiumMg, carbsG, fiberG, sugarG, proteinG, caffeineMg]
            .count { ($0 ?? 0) > 0 }
    }

    private func microFieldCount(_ group: [Micronutrient]) -> Int {
        group.count { (micros[$0.rawValue] ?? 0) > 0 }
    }

    @ViewBuilder
    private func microRows(_ group: [Micronutrient]) -> some View {
        ForEach(group) { micro in
            LabeledContent("\(micro.displayName) (\(micro.unit.symbol))") {
                TextField("—", value: microBinding(micro), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($numberFieldFocused)
            }
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

    private func microBinding(_ micro: Micronutrient) -> Binding<Double?> {
        Binding(
            get: { micros[micro.rawValue] },
            set: { micros[micro.rawValue] = $0 }
        )
    }

    private func nutrientRow(_ label: String, value: Binding<Double?>) -> some View {
        LabeledContent(label) {
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($numberFieldFocused)
        }
    }

    private var formNutrients: NutrientValues {
        NutrientValues(
            fatG: fatG, saturatedFatG: saturatedFatG, transFatG: transFatG,
            polyunsaturatedFatG: polyunsaturatedFatG,
            monounsaturatedFatG: monounsaturatedFatG,
            cholesterolMg: cholesterolMg, carbsG: carbsG, proteinG: proteinG,
            fiberG: fiberG, sugarG: sugarG, caffeineMg: caffeineMg, micros: micros
        )
    }

    private func lookup(_ code: String) async {
        guard SharedStore.onlineLookups else {
            lookupMessage = "Online lookups are off — enable in Settings to look up barcodes."
            return
        }
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            let product = try await OpenFoodFactsClient().product(barcode: code)
            apply(product)
        } catch OpenFoodFactsError.notFound {
            // Back to the camera on the label path rather than a dead
            // end — the panel is in their hand. One turn later: the
            // scanner is still dismissing, and re-presenting into the
            // same slot mid-dismissal dies silently.
            barcode = code
            Task { activeSheet = .scanner(notice: BarcodeRouter.missNotice) }
        } catch {
            // Transient lookup failures toast; lookupMessage stays for
            // the persistent "no calorie data" hint tied to the fields.
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    /// A scanned label prefills through the same funnel as a barcode —
    /// but a label carries no product name or serving text of its own,
    /// so anything already typed survives, and only fields the parser
    /// actually read land (never guessed, per the parser's contract).
    private func applyLabel(_ parsed: ParsedLabel) {
        apply(parsed.scannedProduct(name: name, fallbackServing: serving))
        guard parsed.kcal == nil else {
            lookupMessage = nil
            return
        }
        // A NAME with no numbers came off a sign or a package front, not
        // a panel (SignText, the no-model floor) — so "read the label"
        // describes something that didn't happen. Nor is "no nutrition
        // was printed" the point: a sign never prints any, and reading
        // one is supposed to end in an ESTIMATE. Say which half of the
        // job got done and what would finish it (the user, 2026-08-02).
        guard parsed.name != nil else {
            lookupMessage = "Read the label, but not the calories — check the fields."
            return
        }
        lookupMessage = FoodIntelligence.isAvailable
            ? "Got the name, but couldn't estimate the nutrition — add the calories."
            : "Got the name. Turn on AI in Settings to estimate nutrition from a photo."
    }

    /// The offer's own row: name, serving, and the two figures the app
    /// grades a day on, in the online-result grammar.
    private func publishedRow(_ offer: ScannedProduct) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.name)
                    .foregroundStyle(.primary)
                Text(offer.servingDescription.isEmpty ? "published" : offer.servingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let kcal = offer.kcal {
                    Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal")
                        .monospacedDigit()
                }
                if let sodiumMg = offer.sodiumMg {
                    Text(TrackedNutrient.sodium.captionText(sodiumMg, sodium: sodiumUnit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(.rect)
    }

    /// Taking the published figures REPLACES the estimate, provenance
    /// included: ✨ says "these numbers came from a model", and once they
    /// have been swapped wholesale for a database's, that is no longer
    /// true. (Editing an estimate by hand still keeps the mark — that
    /// changes a number, not where it came from.)
    private func applyPublished(_ offer: ScannedProduct) {
        apply(offer)
        aiGenerated = false
        publishedOffer = nil
    }

    /// Said about the READ, not about the field as it stands now — so it
    /// stays true after the user types the right number in.
    private func caption(for finding: NutritionPlausibility.Finding) -> String {
        switch finding.severity {
        case .dropped: "\(finding.field.displayName) wasn't filled in — \(finding.reason)"
        case .suspect: finding.reason
        }
    }

    private func apply(_ product: ScannedProduct) {
        name = product.name
        kcal = product.kcal
        sodiumMg = product.sodiumMg
        warnings = product.warnings
        serving = product.servingDescription
        barcode = product.barcode.isEmpty ? nil : product.barcode
        fatG = product.nutrients.fatG
        saturatedFatG = product.nutrients.saturatedFatG
        transFatG = product.nutrients.transFatG
        polyunsaturatedFatG = product.nutrients.polyunsaturatedFatG
        monounsaturatedFatG = product.nutrients.monounsaturatedFatG
        cholesterolMg = product.nutrients.cholesterolMg
        carbsG = product.nutrients.carbsG
        proteinG = product.nutrients.proteinG
        fiberG = product.nutrients.fiberG
        sugarG = product.nutrients.sugarG
        caffeineMg = product.nutrients.caffeineMg
        micros = product.nutrients.micros
        // Provenance sticks once set — reviewing/editing an estimate's
        // numbers doesn't change where they came from.
        if product.aiGenerated { aiGenerated = true }
        // An ESTIMATE prefill asks whether a database simply holds this
        // food. One request, silent on failure, and the previous ask is
        // cancelled so a stale offer cannot land on a new food.
        offerTask?.cancel()
        publishedOffer = nil
        if product.aiGenerated, !product.name.isEmpty {
            let name = product.name
            offerTask = Task {
                let match = await PublishedLookup.match(for: name)
                guard !Task.isCancelled else { return }
                publishedOffer = match
            }
        }
        // Only for real lookups (barcode present): a manual "Add Food"
        // prefill carries just the searched name, which isn't a finding.
        lookupMessage = product.kcal == nil && !product.barcode.isEmpty
            ? "Found it, but no calorie data — check the label."
            : nil
        // Every prefill path funnels through here: onAppear prefill,
        // in-form barcode lookup, and the online search pick.
        checkForDuplicate()
    }

    private func save() {
        // The figures are committed; a published-values offer arriving
        // now has nothing left to offer against. Cancelled HERE and at
        // Cancel rather than in an `.onDisappear` — this form USED TO be
        // `.searchable` (retired 2026-08-29, online search moved to the
        // describe field), and that modifier's transient teardown is
        // what turned two sibling cancels into silent dropped work
        // (audit, 2026-08-17) — explicit cancellation at defined points
        // stays the rule regardless. The cost of the paths not covered
        // is one bounded lookup writing into @State that SwiftUI
        // discards. The online search's tasks ride the same rule.
        offerTask?.cancel()
        onlineSearch.clear()
        persist()
        // Every log confirms loudly; a silent edit-save read as a dead
        // button.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) ✓")
        dismiss()
    }

    /// New-food "Save": library only — the meal-building path, where
    /// foods are added without eating them.
    private func saveOnly() {
        persist()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.show(
            "Saved \(name.trimmingCharacters(in: .whitespaces)) to your library ✓"
        )
        dismiss()
    }

    /// "Save & Log" / "Log & Save": persist first (the food survives
    /// every later choice), then straight to the portion sheet.
    private func saveAndLog() {
        persist()
        savedBeforePortion = true
        presentPortionSheet()
    }

    /// The logging route's plain "Log": no library row at all. The
    /// entry lands in HealthKit like any other; the Log sheet's
    /// Recently Logged rows are how it comes back.
    private func logOnly() {
        savedBeforePortion = false
        presentPortionSheet()
    }

    private func presentPortionSheet() {
        portionSheetWasUp = true
        activeSheet = .portion(PortionTarget(
            name: name.trimmingCharacters(in: .whitespaces),
            kcal: kcal ?? 0,
            sodiumMg: sodiumMg ?? 0,
            nutrients: formNutrients,
            serving: serving,
            defaultCategory: PortionTarget.category(from: category),
            aiGenerated: aiGenerated
        ))
    }

    private func sheetDidDismiss() {
        // Only the portion sheet's close carries meaning; the scanner
        // closing is routine.
        guard portionSheetWasUp else { return }
        portionSheetWasUp = false
        guard !portionDidLog else { return }
        // A cancelled portion means opposite things on the two routes,
        // and getting this wrong destroys work. After Save & Log the
        // food is already safely in the library, so saying so and
        // leaving is right. After a plain LOG nothing has been
        // persisted at all — dismissing would silently throw away every
        // typed field, so stay on the form with the values intact.
        // Cancelling a portion is "not that portion", not "discard".
        guard savedBeforePortion else { return }
        ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) to your library ✓ — not logged")
        dismiss()
    }

    private func log(_ target: PortionTarget, quantity: Double, category: FoodCategory) {
        // The form's own log path stamps recency too, or "Recent" would
        // mean "logged from a list" rather than "logged" — an edited
        // food logged straight from Save & Log stayed where it was.
        // `createdFood` covers Save & Log on a brand-new row; the
        // logging-only route has no library twin and stamps nothing.
        if let row = food ?? createdFood {
            row.lastUsedAt = .now
            context.saveOrLog("recency")
        }
        Task {
            let logged = await LogActions.logFood(
                name: target.name,
                kcal: target.kcal * quantity,
                sodiumMg: target.sodiumMg * quantity,
                nutrients: target.nutrients.scaled(by: quantity),
                category: category,
                date: logDate,
                aiGenerated: target.aiGenerated,
                quantity: quantity
            )
            if logged {
                onLogged?()
            }
            dismiss()
        }
    }

    private func persist() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let food = food ?? createdFood {
            food.name = trimmed
            food.kcal = kcal ?? 0
            food.sodiumMg = sodiumMg ?? 0
            food.servingDescription = serving
            food.barcode = barcode
            food.nutrients = formNutrients
            food.category = category
            food.isFavorite = isFavorite
            food.aiGenerated = aiGenerated
        } else {
            let new = Food(
                name: trimmed,
                kcal: kcal ?? 0,
                sodiumMg: sodiumMg ?? 0,
                servingDescription: serving,
                barcode: barcode,
                nutrients: formNutrients,
                isFavorite: isFavorite,
                category: category,
                aiGenerated: aiGenerated
            )
            context.insert(new)
            createdFood = new
        }
        // Explicit save (GoalUpsert's discipline): autosave usually
        // lands this, but a crash/force-quit in the window loses the
        // edit — and the sync push below should read persisted state.
        context.saveOrReport("Couldn't save this food")
        PhoneSyncService.shared.push(from: context)
    }
}
