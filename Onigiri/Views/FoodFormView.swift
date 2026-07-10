import SwiftUI
import SwiftData
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts.
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?
    /// Open the barcode scanner immediately (quick-action entry point).
    var startScanning = false

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
    @State private var category: String?
    @State private var isFavorite = false

    @State private var showScanner = false
    @State private var showSearch = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @FocusState private var numberFieldFocused: Bool

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

                // Nutrition-label order. Trans fat is app-only: Apple
                // Health has no dietary type for it.
                Section("More nutrients") {
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
                }

                Section {
                    DisclosureGroup("Vitamins & minerals", isExpanded: $microsExpanded) {
                        ForEach(Micronutrient.allCases) { micro in
                            LabeledContent("\(micro.displayName) (\(micro.unit.symbol))") {
                                TextField("—", value: microBinding(micro), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($numberFieldFocused)
                            }
                        }
                    }
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || kcal == nil)
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
                    microsExpanded = !micros.isEmpty
                    category = food.category
                    isFavorite = food.isFavorite
                } else if startScanning {
                    showScanner = true
                }
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
        microsExpanded = !micros.isEmpty
        lookupMessage = product.kcal == nil
            ? "Found it, but no calorie data — check the label."
            : nil
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let food {
            food.name = trimmed
            food.kcal = kcal ?? 0
            food.sodiumMg = sodiumMg ?? 0
            food.servingDescription = serving
            food.barcode = barcode
            food.nutrients = formNutrients
            food.category = category
            food.isFavorite = isFavorite
        } else {
            context.insert(Food(
                name: trimmed,
                kcal: kcal ?? 0,
                sodiumMg: sodiumMg ?? 0,
                servingDescription: serving,
                barcode: barcode,
                nutrients: formNutrients,
                isFavorite: isFavorite,
                category: category
            ))
        }
        PhoneSyncService.shared.push(from: context)
        dismiss()
    }
}
