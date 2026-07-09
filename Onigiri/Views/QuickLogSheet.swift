import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// One-stop logging from the Today screen: favorites up top, search below,
/// tap a row to log it and dismiss. Long-press a row for portions.
struct QuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isLogging = false
    @State private var portionTarget: PortionTarget?

    private let health = HealthKitService()

    private struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        let isFavorite: Bool
        let category: String?
    }

    private var allItems: [Item] {
        let mealItems = meals.map { meal in
            Item(
                id: "meal-\(meal.uuid.uuidString)",
                name: meal.name,
                detail: meal.items.compactMap(\.food?.name).joined(separator: ", "),
                kcal: meal.totalKcal,
                sodiumMg: meal.totalSodiumMg,
                nutrients: meal.totalNutrients,
                isFavorite: meal.isFavorite,
                category: meal.category
            )
        }
        let foodItems = foods.map { food in
            Item(
                id: "food-\(food.persistentModelID.hashValue)",
                name: food.name,
                detail: food.servingDescription,
                kcal: food.kcal,
                sodiumMg: food.sodiumMg,
                nutrients: food.nutrients,
                isFavorite: food.isFavorite,
                category: food.category
            )
        }
        return mealItems + foodItems
    }

    private var filtered: [Item] {
        let matched = allItems.filter { item in
            if searchText.isEmpty { return true }
            if item.name.localizedCaseInsensitiveContains(searchText) { return true }
            return item.category?.localizedCaseInsensitiveContains(searchText) ?? false
        }
        return matched.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var favorites: [Item] {
        filtered.filter(\.isFavorite)
    }

    private var others: [Item] {
        filtered.filter { !$0.isFavorite }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { item in
                            row(item)
                        }
                    }
                }
                Section(favorites.isEmpty ? "Library" : "Everything else") {
                    ForEach(others) { item in
                        row(item)
                    }
                    if filtered.isEmpty {
                        Text(allItems.isEmpty
                             ? "No saved foods yet — add some in the Foods tab first."
                             : "No matches.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search foods, meals, categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $portionTarget) { target in
                PortionSheet(target: target) { quantity in
                    log(
                        Item(id: target.name, name: target.name, detail: target.serving,
                             kcal: target.kcal, sodiumMg: target.sodiumMg,
                             nutrients: target.nutrients, isFavorite: false, category: nil),
                        quantity: quantity
                    )
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func row(_ item: Item) -> some View {
        LibraryRow(
            name: item.name,
            detail: item.detail,
            kcal: item.kcal,
            sodiumMg: item.sodiumMg,
            isFavorite: item.isFavorite
        )
        .contentShape(.rect)
        .onTapGesture {
            log(item, quantity: 1)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            portionTarget = PortionTarget(
                name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
                nutrients: item.nutrients, serving: item.detail
            )
        }
        .accessibilityAddTraits(.isButton)
    }

    private func log(_ item: Item, quantity: Double) {
        guard !isLogging else { return }
        isLogging = true
        Task {
            do {
                try await health.logFood(
                    name: item.name,
                    kcal: item.kcal * quantity,
                    sodiumMg: item.sodiumMg * quantity,
                    nutrients: item.nutrients.scaled(by: quantity)
                )
                WidgetCenter.shared.reloadAllTimelines()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = "Couldn't log: \(error.localizedDescription)"
                isLogging = false
            }
        }
    }
}

#Preview {
    QuickLogSheet()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
