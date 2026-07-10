import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts. The one surface every new food passes through — Save
/// keeps it in the library, Save & Log also confirms a portion and logs it.
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?
    /// Open the barcode scanner immediately (quick-action entry point).
    var startScanning = false
    /// Prefill from a scanned/searched product (new-food log flow).
    var prefill: ScannedProduct?
    /// Called after Save & Log completes, so the presenter can dismiss too.
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
    @State private var nutrientsExpanded = false
    @State private var category: String?
    @State private var isFavorite = false

    @State private var showScanner = false
    @State private var showSearch = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var portionTarget: PortionTarget?
    /// A new food inserted by Save & Log, so a second save updates it
    /// instead of inserting a duplicate.
    @State private var createdFood: Food?
    @FocusState private var numberFieldFocused: Bool

    private let health = HealthKitService()

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

                // Both nutrient groups start collapsed so Save & Log stays
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
                        groupLabel("More nutrients", filled: nutrientFieldCount)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $microsExpanded) {
                        ForEach(Micronutrient.allCases) { micro in
                            LabeledContent("\(micro.displayName) (\(micro.unit.symbol))") {
                                TextField("—", value: microBinding(micro), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($numberFieldFocused)
                            }
                        }
                    } label: {
                        groupLabel("Vitamins & minerals", filled: micros.count)
                    }
                }

                Section {
                    Button {
                        saveAndLog()
                    } label: {
                        Text("Save & Log")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ricePaper)
                    .listRowInsets(EdgeInsets())
                    .disabled(!canSave)
                } footer: {
                    Text("Saves to your library, then confirms the portion and logs it.")
                }
            }
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
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
                guard let field = note.object as? UITextField else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
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
            .sheet(item: $portionTarget) { target in
                PortionSheet(target: target) { quantity, category in
                    log(target, quantity: quantity, category: category)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if let food {
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
                } else if let prefill {
                    apply(prefill)
                } else if startScanning {
                    showScanner = true
                }
            }
        }
    }

    private var nutrientFieldCount: Int {
        [fatG, saturatedFatG, transFatG, polyunsaturatedFatG, monounsaturatedFatG,
         cholesterolMg, sodiumMg, carbsG, fiberG, sugarG, proteinG, caffeineMg]
            .compactMap { $0 }.count
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
        do {
            let product = try await OpenFoodFactsClient().product(barcode: code)
            apply(product)
        } catch {
            lookupMessage = error.localizedDescription
        }
        isLookingUp = false
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
        lookupMessage = product.kcal == nil
            ? "Found it, but no calorie data — check the label."
            : nil
    }

    private func save() {
        persist()
        dismiss()
    }

    /// Save to the library, then confirm a portion to log. Persisting first
    /// means the food survives even if the portion sheet is cancelled.
    private func saveAndLog() {
        persist()
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
            do {
                try await health.logFood(
                    name: target.name,
                    kcal: target.kcal * quantity,
                    sodiumMg: target.sodiumMg * quantity,
                    nutrients: target.nutrients.scaled(by: quantity),
                    category: category
                )
                WidgetCenter.shared.reloadAllTimelines()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onLogged?()
                dismiss()
            } catch {
                lookupMessage = "Saved, but couldn't log: \(error.localizedDescription)"
            }
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
