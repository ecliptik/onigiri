import SwiftUI
import SwiftData
import OnigiriKit

/// Create or edit a one-tap meal by picking quantities of saved foods.
struct MealFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]

    var meal: Meal?

    @State private var name = ""
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var category: String?
    @State private var isFavorite = false
    @State private var foodFilter = ""
    /// Recent-first by default (the user — the foods you just added are
    /// the ones the meal is for); remembered across builds. Shares the
    /// Foods screen's option set (Favorites / Recent / Name).
    @AppStorage("mealBuilderSort") private var sortRaw = LibrarySort.recent.rawValue

    private var librarySort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }
    // The Total's secondary metric follows the first tracked slot (the
    // user: sodium was hardcoded; now it customizes with Settings).
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var libraryMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }
    /// Cancel/drag with edits confirms first — a half-built meal used
    /// to vanish on a stray swipe.
    @State private var confirmDiscard = false
    @State private var initialSnapshot: FieldsSnapshot?
    @State private var isSuggestingName = false
    @FocusState private var quantityFocused: Bool

    private struct FieldsSnapshot: Equatable {
        var name: String
        var quantities: [PersistentIdentifier: Double]
        var category: String?
        var isFavorite: Bool
    }

    private var currentSnapshot: FieldsSnapshot {
        FieldsSnapshot(
            // Zero quantities are "not in the meal" — same as absent.
            name: name, quantities: quantities.filter { $0.value > 0 },
            category: category, isFavorite: isFavorite
        )
    }

    private var isDirty: Bool {
        initialSnapshot.map { $0 != currentSnapshot } ?? false
    }

    /// Foods shown in the picker list; totals still count every selected
    /// food, filtered out of view or not.
    private var visibleFoods: [Food] {
        let trimmed = foodFilter.trimmingCharacters(in: .whitespaces)
        var pool = foods
        if !trimmed.isEmpty {
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        // The @Query is name-sorted; the other orders re-sort here (ties
        // break alphabetically, which the stable base order provides).
        switch librarySort {
        case .ranked:
            return pool.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.recencyDate > $1.recencyDate
            }
        case .recent:
            return pool.sorted { $0.recencyDate > $1.recencyDate }
        case .name:
            return pool
        }
    }

    private var totalKcal: Double {
        foods.reduce(0) { $0 + $1.kcal * (quantities[$1.persistentModelID] ?? 0) }
    }
    private var totalMetricAmount: Double {
        foods.reduce(0) { sum, food in
            let quantity = quantities[food.persistentModelID] ?? 0
            guard quantity > 0 else { return sum }
            let amount = libraryMetric.itemAmount(sodiumMg: food.sodiumMg, nutrients: food.nutrients) ?? 0
            return sum + amount * quantity
        }
    }
    private var hasItems: Bool { quantities.values.contains { $0 > 0 } }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Meal name", text: $name)
                    // One tap, one on-device suggestion, freely edited or
                    // retried — only on Apple Intelligence devices, and
                    // only once there are foods to name.
                    if FoodIntelligence.isAvailable, hasItems {
                        Button {
                            suggestName()
                        } label: {
                            if isSuggestingName {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color.riceToast)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSuggestingName)
                        .accessibilityLabel("Suggest meal name")
                    }
                }
                Picker("Category", selection: $category) {
                    Text("None").tag(String?.none)
                    ForEach(FoodCategory.allCases) { option in
                        Text(option.rawValue).tag(String?.some(option.rawValue))
                    }
                }
                Toggle("Favorite", isOn: $isFavorite)
                // The running size of the meal, visible while picking
                // foods below (the user — the old bottom Total sat off
                // screen exactly when it was needed).
                LabeledContent("Total") {
                    Text("\(totalKcal, format: .number.precision(.fractionLength(0))) kcal • \(totalMetricAmount, format: .number.precision(.fractionLength(0...1))) \(libraryMetric.captionUnit)")
                        .monospacedDigit()
                        .foregroundStyle(hasItems ? .primary : .secondary)
                }

                Section {
                    ForEach(visibleFoods) { food in
                        // Quarter-step ± plus a TYPED quantity, exactly
                        // like the portion sheet — half a Soylent belongs
                        // in a meal (the user). The field bypasses the
                        // Stepper's range, so clamp in the binding too.
                        Stepper(value: binding(for: food), in: 0...20, step: 0.25) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                    Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField("—", value: typedBinding(for: food),
                                          format: .number.precision(.fractionLength(0...2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 56)
                                    .monospacedDigit()
                                    .focused($quantityFocused)
                                    .accessibilityLabel("Servings of \(food.name)")
                            }
                            .padding(.trailing, 8)
                        }
                    }
                    if visibleFoods.isEmpty {
                        // `No foods match “”.` rendered for an emptied
                        // library.
                        Text(foodFilter.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "No saved foods yet — add foods on the Library tab first."
                            : "No foods match “\(foodFilter.trimmingCharacters(in: .whitespaces))”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Foods")
                        Spacer()
                        // Recent leads; the menu swaps order (remembered).
                        Menu {
                            Picker("Sort", selection: $sortRaw) {
                                ForEach(LibrarySort.allCases, id: \.rawValue) { option in
                                    Text(option.label).tag(option.rawValue)
                                }
                            }
                        } label: {
                            Label(librarySort.label,
                                  systemImage: "arrow.up.arrow.down")
                                .font(.footnote)
                        }
                        .textCase(nil)
                        .accessibilityLabel("Sort foods")
                    }
                }
            }
            .compactSections()
            .riceCanvas()
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            // System search, matching Foods and the Log sheet (bottom
            // placement on iOS 26).
            .searchable(text: $foodFilter, prompt: "Search foods")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasItems)
                }
                // Decimal pads have no return key; surface a Done while a
                // quantity field is editing (the food form's pattern).
                if quantityFocused {
                    ToolbarItem(placement: .principal) {
                        Button {
                            quantityFocused = false
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
            // .immediately, not .interactively: after typing a portion
            // the pad stays up, and the very next gesture is a scroll to
            // find the NEXT food — the keyboard must not eat half the
            // list (the user).
            .scrollDismissesKeyboard(.immediately)
            // Select-all on focus so typing replaces a portion instead
            // of appending to it (the food form's pattern). The system
            // search field is exempt — selecting an in-progress query on
            // refocus would surprise.
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )) { note in
                guard let field = note.object as? UITextField,
                      !(field is UISearchTextField) else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(isDirty)
            .onAppear {
                if let meal {
                    name = meal.name
                    category = meal.category
                    isFavorite = meal.isFavorite
                    quantities = Dictionary(uniqueKeysWithValues: meal.items.compactMap { item in
                        item.food.map { ($0.persistentModelID, item.quantity) }
                    })
                }
                initialSnapshot = currentSnapshot
            }
        }
    }

    /// Fills the name field with the model's suggestion; any failure
    /// just leaves the field as it was.
    private func suggestName() {
        let members = foods
            .filter { (quantities[$0.persistentModelID] ?? 0) > 0 }
            .map(\.name)
        guard !members.isEmpty, !isSuggestingName else { return }
        isSuggestingName = true
        Task {
            defer { isSuggestingName = false }
            if let suggestion = await FoodIntelligence.suggestMealName(for: members) {
                name = suggestion
            }
        }
    }

    private func binding(for food: Food) -> Binding<Double> {
        Binding(
            get: { quantities[food.persistentModelID] ?? 0 },
            set: { newValue in
                // The first + selects ONE serving (the default portion),
                // not a quarter of one; ± nudges by quarters from there.
                let old = quantities[food.persistentModelID] ?? 0
                quantities[food.persistentModelID] = (old == 0 && newValue == 0.25) ? 1 : newValue
            }
        )
    }

    /// The typed-quantity flavor: empty shows the "—" placeholder
    /// instead of a wall of zeros, and typed values clamp to the
    /// stepper's range (0.01 minimum — 0 means "not in the meal",
    /// reached by clearing the field).
    private func typedBinding(for food: Food) -> Binding<Double?> {
        Binding(
            get: {
                let quantity = quantities[food.persistentModelID] ?? 0
                return quantity > 0 ? quantity : nil
            },
            set: { newValue in
                guard let newValue, newValue > 0 else {
                    quantities[food.persistentModelID] = 0
                    return
                }
                quantities[food.persistentModelID] = min(newValue, 20)
            }
        )
    }

    private func save() {
        // Every log confirms loudly; a silent edit-save read as a dead
        // button.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) ✓")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let items = foods.compactMap { food -> MealItem? in
            let quantity = quantities[food.persistentModelID] ?? 0
            return quantity > 0 ? MealItem(food: food, quantity: quantity) : nil
        }
        if let meal {
            meal.name = trimmed
            meal.category = category
            meal.isFavorite = isFavorite
            // Unlink before deleting: deleting items the meal still
            // references is the dangling-reference crash class.
            let oldItems = meal.items
            meal.items = items
            oldItems.forEach(context.delete)
        } else {
            context.insert(Meal(name: trimmed, items: items, isFavorite: isFavorite, category: category))
        }
        PhoneSyncService.shared.push(from: context)
        dismiss()
    }
}
