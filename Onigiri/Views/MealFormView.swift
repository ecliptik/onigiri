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
    /// Cancel/drag with edits confirms first — a half-built meal used
    /// to vanish on a stray swipe.
    @State private var confirmDiscard = false
    @State private var initialSnapshot: FieldsSnapshot?

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
        guard !trimmed.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var totalKcal: Double {
        foods.reduce(0) { $0 + $1.kcal * (quantities[$1.persistentModelID] ?? 0) }
    }
    private var totalSodiumMg: Double {
        foods.reduce(0) { $0 + $1.sodiumMg * (quantities[$1.persistentModelID] ?? 0) }
    }
    private var hasItems: Bool { quantities.values.contains { $0 > 0 } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal name", text: $name)
                Picker("Category", selection: $category) {
                    Text("None").tag(String?.none)
                    ForEach(FoodCategory.allCases) { option in
                        Text(option.rawValue).tag(String?.some(option.rawValue))
                    }
                }
                Toggle("Favorite", isOn: $isFavorite)

                Section("Foods") {
                    ForEach(visibleFoods) { food in
                        // Quarter steps plus a typed quantity, like the
                        // portion sheet — the builder was integer-only
                        // while logging celebrated 0.85 servings.
                        Stepper(value: binding(for: food), in: 0...20, step: 0.25) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                    Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                let quantity = quantities[food.persistentModelID] ?? 0
                                Text(quantity > 0 ? "×\(quantity, format: .number.precision(.fractionLength(0...2)))" : "—")
                                    .foregroundStyle(quantity > 0 ? .primary : .secondary)
                                    .monospacedDigit()
                            }
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
                }

                Section {
                    LabeledContent("Total") {
                        Text("\(totalKcal, format: .number.precision(.fractionLength(0))) kcal • \(totalSodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                            .monospacedDigit()
                    }
                }
            }
            .compactSections()
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

    private func binding(for food: Food) -> Binding<Double> {
        Binding(
            get: { quantities[food.persistentModelID] ?? 0 },
            set: { quantities[food.persistentModelID] = $0 }
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
