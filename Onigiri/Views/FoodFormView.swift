import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts. The one surface every new food passes through — Save
/// keeps it library-only (the meal-building path), Save & Log continues
/// to the portion sheet.
struct FoodFormView: View {
    /// The field names what it queries — one database or both.
    static var searchPrompt: String {
        switch SharedStore.textSearchMode {
        case .openFoodFacts: "Search OpenFoodFacts"
        case .fdc: "Search USDA"
        case .both: "Search online databases"
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?
    /// Open the barcode scanner immediately (quick-action entry point).
    var startScanning = false
    /// Prefill from a scanned/searched product (new-food log flow).
    var prefill: ScannedProduct?
    /// Timestamp for the entry the Log action writes (backfill support).
    var logDate: Date = .now
    /// Called after the Log action completes, so the presenter can dismiss too.
    var onLogged: (() -> Void)?

    @State private var name = ""
    @State private var kcal: Double?
    @State private var sodiumMg: Double?
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

    /// One item drives both scanner sheets — chained .sheet modifiers on
    /// one view compete (the SwiftData-era landmine list).
    private enum ScannerKind: String, Identifiable {
        case barcode, label
        var id: String { rawValue }
    }
    @State private var activeScanner: ScannerKind?
    /// The in-form OpenFoodFacts search: the STANDARD system field
    /// (bottom-placed), results inline via the shared section — the
    /// separate Search Database sheet is retired.
    @State private var dbQuery = ""
    @State private var dbSearchActive = false
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    /// "Describe it" quick add (iOS 26 + Apple Intelligence only; the
    /// field does not exist on other devices).
    @State private var describeText = ""
    @State private var isEstimating = false
    @State private var portionTarget: PortionTarget?
    @State private var portionDidLog = false
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

    var body: some View {
        NavigationStack {
            searchableForm
                .navigationTitle(food == nil && createdFood == nil ? "New Food" : "Edit Food")
                .navigationBarTitleDisplayMode(.inline)
        }
        .toastHost()
    }

    /// The scanner and online search exist to FILL a blank form. A form
    /// opened FROM a search result (or editing a saved food) offering
    /// another search was a loop — they render only for a blank new
    /// food, the Library-screen add path.
    private var isBlankNewFood: Bool {
        food == nil && prefill == nil && createdFood == nil
    }

    @ViewBuilder
    private var searchableForm: some View {
        if isBlankNewFood {
            formContent
                // The STANDARD system search field, bottom-placed like
                // the Log sheet's — the barcode scanner sits in the top
                // section (the system field can't host it).
                .searchable(
                    text: $dbQuery,
                    isPresented: $dbSearchActive,
                    prompt: Self.searchPrompt
                )
                .onSubmit(of: .search) {
                    Task { await onlineSearch.search(dbQuery) }
                }
                .onChange(of: dbQuery) { _, text in
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        onlineSearch.clear()
                    }
                }
        } else {
            formContent
        }
    }

    private var formContent: some View {
            Form {
                // The scanner leads the form as a labeled row (Micheal's
                // pick — the toolbar icon crowded the Save cluster);
                // lookup status lands right beneath it. The search field
                // lives at the bottom, system placement.
                if isBlankNewFood {
                Section {
                    Button {
                        activeScanner = .barcode
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    .disabled(isLookingUp)
                    // The third door: label OCR for foods no database
                    // knows (store brands, imports, no barcode at all).
                    Button {
                        activeScanner = .label
                    } label: {
                        Label("Scan Label", systemImage: "text.viewfinder")
                    }
                    .disabled(isLookingUp)
                    if isLookingUp {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking up product…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                }

                // "Describe it": plain language → on-device estimate,
                // reviewed right here in the form. Renders only when the
                // Apple Intelligence model is actually available — no AI
                // affordance exists anywhere else.
                if isBlankNewFood, FoodIntelligence.isAvailable {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.riceToast)
                            TextField(
                                "Describe it — half cup rice, fried egg",
                                text: $describeText
                            )
                            .onSubmit { estimateFromDescription() }
                            .submitLabel(.done)
                        }
                        if isEstimating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Estimating…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("On-device estimates — review before saving.")
                    }
                }

                // Inline OpenFoodFacts results (the shared section) —
                // picking one prefills the fields below.
                if isBlankNewFood, !dbQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: dbQuery, search: onlineSearch, onPick: { product in
                        apply(product)
                        endDatabaseSearch()
                    }, onAddManually: { pickedName in
                        name = pickedName
                        endDatabaseSearch()
                    })
                }

                Section {
                    TextField("Name", text: $name)
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
                        nutrientRow("Sodium (mg)", value: $sodiumMg)
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
                            dismiss()
                        }
                    }
                }
                // New foods: Save keeps it library-only (meal building);
                // Save & Log continues to the portion sheet. Two toolbar
                // buttons replace the old post-save "Log it?" alert — a
                // whole modal for a yes/no.
                ToolbarItemGroup(placement: .confirmationAction) {
                    if food == nil {
                        Button("Save") { saveOnly() }
                            .disabled(!canSave)
                        Button("Save & Log") { saveAndLog() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    } else {
                        Button("Save") { save() }
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
                // not inherit the select-all. The bottom search field is
                // exempt too — selecting-all an in-progress query on
                // refocus would surprise.
                guard activeScanner == nil, !dbSearchActive, portionTarget == nil,
                      let field = note.object as? UITextField else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            // On a background layer: two .alert modifiers chained on the
            // same view compete, like the .sheet landmine.
            .background {
                Color.clear.alert(
                    "“\(duplicateMatch?.name ?? "")” is already in your library",
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
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(isDirty)
            .sheet(item: $activeScanner) { kind in
                switch kind {
                case .barcode:
                    BarcodeScannerSheet { code in
                        Task { await lookup(code) }
                    }
                case .label:
                    LabelScannerSheet { parsed in
                        applyLabel(parsed)
                    }
                }
            }
            .sheet(item: $portionTarget, onDismiss: {
                // Cancelled portion after Log: the save already happened —
                // say so instead of silently keeping it.
                guard !portionDidLog else { return }
                ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) to your library ✓ — not logged")
                dismiss()
            }) { target in
                PortionSheet(target: target) { quantity, category, _ in
                    portionDidLog = true
                    log(target, quantity: quantity, category: category)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if let food {
                    loadFields(from: food)
                } else if let prefill {
                    apply(prefill)
                } else if startScanning {
                    activeScanner = .barcode
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

    /// A database pick landed in the fields — retire the search UI.
    private func endDatabaseSearch() {
        dbQuery = ""
        dbSearchActive = false
        onlineSearch.clear()
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
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            let product = try await OpenFoodFactsClient().product(barcode: code)
            apply(product)
        } catch {
            // Transient lookup failures toast; lookupMessage stays for
            // the persistent "no calorie data" hint tied to the fields.
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    /// "Describe it" → on-device estimate → the same prefill funnel,
    /// marked clearly as an estimate. Failure (or the model declining)
    /// leaves the form exactly as typed.
    private func estimateFromDescription() {
        let description = describeText.trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty, !isEstimating else { return }
        isEstimating = true
        Task {
            defer { isEstimating = false }
            guard let estimate = await FoodIntelligence.describeFood(description) else {
                lookupMessage = "Couldn't estimate that — add the numbers by hand."
                return
            }
            apply(ScannedProduct(
                barcode: "",
                name: estimate.name,
                kcal: estimate.kcal,
                sodiumMg: estimate.sodiumMg,
                servingDescription: estimate.serving,
                nutrients: NutrientValues()
            ))
            describeText = ""
            lookupMessage = "On-device estimate — review before saving."
        }
    }

    /// A scanned label prefills through the same funnel as a barcode —
    /// but a label carries no product name or serving text of its own,
    /// so anything already typed survives, and only fields the parser
    /// actually read land (never guessed, per the parser's contract).
    private func applyLabel(_ parsed: ParsedLabel) {
        apply(ScannedProduct(
            barcode: "",
            name: name,
            kcal: parsed.kcal,
            sodiumMg: parsed.sodiumMg,
            servingDescription: parsed.servingDescription ?? serving,
            nutrients: parsed.nutrients
        ))
        lookupMessage = parsed.kcal == nil
            ? "Read the label, but not the calories — check the fields."
            : nil
    }

    private func apply(_ product: ScannedProduct) {
        name = product.name
        kcal = product.kcal
        sodiumMg = product.sodiumMg
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

    /// New-food "Save & Log": persist first (the food survives every
    /// later choice), then straight to the portion sheet.
    private func saveAndLog() {
        persist()
        presentPortionSheet()
    }

    private func presentPortionSheet() {
        portionTarget = PortionTarget(
            name: name.trimmingCharacters(in: .whitespaces),
            kcal: kcal ?? 0,
            sodiumMg: sodiumMg ?? 0,
            nutrients: formNutrients,
            serving: serving,
            defaultCategory: PortionTarget.category(from: category)
        )
    }

    private func log(_ target: PortionTarget, quantity: Double, category: FoodCategory) {
        Task {
            let logged = await LogActions.logFood(
                name: target.name,
                kcal: target.kcal * quantity,
                sodiumMg: target.sodiumMg * quantity,
                nutrients: target.nutrients.scaled(by: quantity),
                category: category,
                date: logDate
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
        } else {
            let new = Food(
                name: trimmed,
                kcal: kcal ?? 0,
                sodiumMg: sodiumMg ?? 0,
                servingDescription: serving,
                barcode: barcode,
                nutrients: formNutrients,
                isFavorite: isFavorite,
                category: category
            )
            context.insert(new)
            createdFood = new
        }
        PhoneSyncService.shared.push(from: context)
    }
}
