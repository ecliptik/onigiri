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
                        Stepper(value: binding(for: food), in: 0...20, step: 1) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                    Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                let quantity = quantities[food.persistentModelID] ?? 0
                                Text(quantity > 0 ? "×\(quantity, format: .number.precision(.fractionLength(0)))" : "—")
                                    .foregroundStyle(quantity > 0 ? .primary : .secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if visibleFoods.isEmpty {
                        Text("No foods match “\(foodFilter.trimmingCharacters(in: .whitespaces))”.")
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasItems)
                }
            }
            .onAppear {
                if let meal {
                    name = meal.name
                    category = meal.category
                    isFavorite = meal.isFavorite
                    quantities = Dictionary(uniqueKeysWithValues: meal.items.compactMap { item in
                        item.food.map { ($0.persistentModelID, item.quantity) }
                    })
                }
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let items = foods.compactMap { food -> MealItem? in
            let quantity = quantities[food.persistentModelID] ?? 0
            return quantity > 0 ? MealItem(food: food, quantity: quantity) : nil
        }
        if let meal {
            meal.name = trimmed
            meal.category = category
            meal.isFavorite = isFavorite
            meal.items.forEach(context.delete)
            meal.items = items
        } else {
            context.insert(Meal(name: trimmed, items: items, isFavorite: isFavorite, category: category))
        }
        PhoneSyncService.shared.push(from: context)
        dismiss()
    }
}
