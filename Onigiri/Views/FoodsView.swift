import SwiftUI
import SwiftData
import OnigiriKit

/// The library: saved foods and one-tap meals. Tapping a row logs it to
/// HealthKit immediately — the fast path for recurring meals.
struct FoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]

    @State private var showNewFood = false
    @State private var showNewMeal = false
    @State private var editingFood: Food?
    @State private var toast: String?

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            List {
                if !meals.isEmpty {
                    Section("Meals — tap to log") {
                        ForEach(meals) { meal in
                            Button {
                                log(name: meal.name, kcal: meal.totalKcal, sodiumMg: meal.totalSodiumMg)
                            } label: {
                                LibraryRow(
                                    name: meal.name,
                                    detail: meal.items.compactMap(\.food?.name).joined(separator: ", "),
                                    kcal: meal.totalKcal,
                                    sodiumMg: meal.totalSodiumMg
                                )
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { meals[$0] }.forEach(context.delete)
                        }
                    }
                }

                Section(foods.isEmpty ? "Foods" : "Foods — tap to log") {
                    ForEach(foods) { food in
                        Button {
                            log(name: food.name, kcal: food.kcal, sodiumMg: food.sodiumMg)
                        } label: {
                            LibraryRow(
                                name: food.name,
                                detail: food.servingDescription,
                                kcal: food.kcal,
                                sodiumMg: food.sodiumMg
                            )
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingFood = food }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { foods[$0] }.forEach(context.delete)
                    }

                    if foods.isEmpty {
                        ContentUnavailableView(
                            "No foods yet",
                            systemImage: "fork.knife",
                            description: Text("Add a food once — calories and sodium off the label — then log it any day with a tap.")
                        )
                    }
                }
            }
            .navigationTitle("Foods")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Food", systemImage: "carrot") { showNewFood = true }
                        Button("Add Meal", systemImage: "takeoutbag.and.cup.and.straw") { showNewMeal = true }
                            .disabled(foods.isEmpty)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewFood) { FoodFormView(food: nil) }
            .sheet(item: $editingFood) { FoodFormView(food: $0) }
            .sheet(isPresented: $showNewMeal) { MealFormView() }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: toast)
        }
    }

    private func log(name: String, kcal: Double, sodiumMg: Double) {
        Task {
            do {
                try await health.logFood(name: name, kcal: kcal, sodiumMg: sodiumMg)
                showToast("Logged \(name) ✓")
            } catch {
                showToast("Couldn't log: \(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

struct LibraryRow: View {
    let name: String
    let detail: String
    let kcal: Double
    let sodiumMg: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("\(sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
