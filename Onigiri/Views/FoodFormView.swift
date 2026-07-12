import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts. The one surface every new food passes through — Save
/// persists to the library, then offers to log a portion (declining is
/// the meal-building path).
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var libraryFoods: [Food]

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

    @State private var showScanner = false
    @State private var showSearch = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var portionTarget: PortionTarget?
    @State private var portionDidLog = false
    /// The post-save "Log it?" prompt for new foods.
    @State private var askToLog = false
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // One row: text search on the left, barcode scan on
                    // the right.
                    HStack {
                        Button {
                            showSearch = true
                        } label: {
                            Label("Search database", systemImage: "magnifyingglass")
                        }
                        Spacer()
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundStyle(Color.riceToast)
                        }
                        .accessibilityLabel("Scan barcode")
                    }
                    .buttonStyle(.borderless)
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

            }
            .compactSections()
            .navigationTitle(food == nil && createdFood == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // New foods save first, then OFFER to log — building a
                    // meal means adding foods without logging them.
                    if food == nil {
                        Button("Save") { saveAndAskToLog() }
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
                                .foregroundStyle(.black)
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
                // own sheets is up (scanner, online search, portion), its
                // fields must not inherit the select-all.
                guard !showScanner, !showSearch, portionTarget == nil,
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
                    Button("Create New") {}
                } message: { _ in
                    Text("Edit keeps your saved values and attaches this barcode; Create New makes a separate food.")
                }
            }
            .alert(
                "Log “\(name.trimmingCharacters(in: .whitespaces))”?",
                isPresented: $askToLog
            ) {
                Button("Log") { presentPortionSheet() }
                Button("Not Now", role: .cancel) {
                    ToastCenter.shared.show(
                        "Saved \(name.trimmingCharacters(in: .whitespaces)) to your library ✓"
                    )
                    dismiss()
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { code in
                    Task { await lookup(code) }
                }
            }
            .sheet(isPresented: $showSearch) {
                FoodSearchSheet(initialQuery: name) { product in
                    apply(product)
                }
            }
            .sheet(item: $portionTarget, onDismiss: {
                // Cancelled portion after Log: the save already happened —
                // say so instead of silently keeping it.
                guard !portionDidLog else { return }
                ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) to your library ✓ — not logged")
                dismiss()
            }) { target in
                PortionSheet(target: target) { quantity, category in
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
                    showScanner = true
                }
            }
        }
        .toastHost()
    }

    /// Duplicate-food guard: fires only for NEW foods whose prefilled
    /// name is already in the library (Micheal's manual-entry-then-scan
    /// case). Manual typing is not guarded — that's deliberate.
    private func checkForDuplicate() {
        guard food == nil, createdFood == nil else { return }
        duplicateMatch = libraryFoods.first {
            LibraryDuplicate.nameMatches($0.name, name)
        }
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
        dismiss()
    }

    /// New-food flow: persist first (the food survives every later
    /// choice), then offer to log it — declining is the meal-building
    /// path, where foods are added without eating them.
    private func saveAndAskToLog() {
        persist()
        askToLog = true
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
