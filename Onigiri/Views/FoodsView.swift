import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// The library: saved foods and one-tap meals. Tapping a row logs it to
/// HealthKit immediately — the fast path for recurring meals. Searchable,
/// filterable by category, with favorites floating to the top.
struct FoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]

    /// Set by the "Scan Barcode" quick action: open a new-food form scanning.
    @Binding var scanRequest: Bool

    @State private var showNewFood = false
    @State private var showScanFood = false
    @State private var showNewMeal = false
    @State private var editingFood: Food?
    @State private var editingMeal: Meal?
    @State private var toast: String?
    @State private var undoLogID: UUID?
    @State private var searchText = ""
    @State private var categoryFilter: FoodCategory?

    private let health = HealthKitService()

    private var filteredMeals: [Meal] {
        meals
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredFoods: [Food] {
        foods
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func matches(name: String, category: String?) -> Bool {
        if let filter = categoryFilter, category != filter.rawValue { return false }
        if searchText.isEmpty { return true }
        return name.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredMeals.isEmpty {
                    Section("Meals") {
                        ForEach(filteredMeals) { meal in
                            HStack(spacing: 10) {
                                LibraryRow(
                                    name: meal.name,
                                    detail: meal.items.compactMap(\.food?.name).joined(separator: ", "),
                                    kcal: meal.totalKcal,
                                    sodiumMg: meal.totalSodiumMg,
                                    isFavorite: meal.isFavorite
                                )
                                LogButton(name: meal.name) {
                                    log(name: meal.name, kcal: meal.totalKcal,
                                        sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { editingMeal = meal }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingMeal = meal
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.riceToast)
                                Button {
                                    meal.isFavorite.toggle()
                                } label: {
                                    Label("Favorite", systemImage: meal.isFavorite ? "star.slash" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingMeal = meal }
                                Button(meal.isFavorite ? "Unfavorite" : "Favorite",
                                       systemImage: meal.isFavorite ? "star.slash" : "star.fill") {
                                    meal.isFavorite.toggle()
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { filteredMeals[$0] }.forEach(context.delete)
                        }
                    }
                }

                Section("Foods") {
                    ForEach(filteredFoods) { food in
                        HStack(spacing: 10) {
                            LibraryRow(
                                name: food.name,
                                detail: food.servingDescription,
                                kcal: food.kcal,
                                sodiumMg: food.sodiumMg,
                                isFavorite: food.isFavorite
                            )
                            LogButton(name: food.name) {
                                log(name: food.name, kcal: food.kcal,
                                    sodiumMg: food.sodiumMg, nutrients: food.nutrients)
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture { editingFood = food }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingFood = food
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.riceToast)
                            Button {
                                food.isFavorite.toggle()
                            } label: {
                                Label("Favorite", systemImage: food.isFavorite ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingFood = food }
                            Button(food.isFavorite ? "Unfavorite" : "Favorite",
                                   systemImage: food.isFavorite ? "star.slash" : "star.fill") {
                                food.isFavorite.toggle()
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filteredFoods[$0] }.forEach(context.delete)
                    }

                    if foods.isEmpty {
                        ContentUnavailableView(
                            "No foods yet",
                            systemImage: "fork.knife",
                            description: Text("Add a food once — calories and sodium off the label — then log it any day with a tap.")
                        )
                    } else if filteredFoods.isEmpty && filteredMeals.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .navigationTitle("Foods")
            .searchable(text: $searchText, prompt: "Search foods and meals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Category", selection: $categoryFilter) {
                            Text("All").tag(FoodCategory?.none)
                            ForEach(FoodCategory.allCases) { option in
                                Text(option.rawValue).tag(FoodCategory?.some(option))
                            }
                        }
                    } label: {
                        Image(systemName: categoryFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Food", systemImage: "carrot") { showNewFood = true }
                        Button("Add Meal", systemImage: "takeoutbag.and.cup.and.straw") { showNewMeal = true }
                            .disabled(foods.isEmpty)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $showNewFood) { FoodFormView(food: nil) }
            .sheet(isPresented: $showScanFood) { FoodFormView(food: nil, startScanning: true) }
            .sheet(item: $editingFood) { FoodFormView(food: $0) }
            .sheet(isPresented: $showNewMeal) { MealFormView() }
            .sheet(item: $editingMeal) { MealFormView(meal: $0) }
            .task {
                if scanRequest {
                    scanRequest = false
                    showScanFood = true
                }
            }
            .onChange(of: scanRequest) { _, requested in
                if requested {
                    scanRequest = false
                    showScanFood = true
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    HStack(spacing: 12) {
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                        if let undoID = undoLogID {
                            Button("Undo") {
                                undo(undoID)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.riceToast)
                        }
                    }
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

    private func log(name: String, kcal: Double, sodiumMg: Double, nutrients: NutrientValues) {
        Task {
            do {
                let id = try await health.logFood(name: name, kcal: kcal, sodiumMg: sodiumMg, nutrients: nutrients)
                undoLogID = id
                showToast("Logged \(name) ✓", clearsUndo: true)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                undoLogID = nil
                showToast("Couldn't log: \(error.localizedDescription)")
            }
        }
    }

    private func undo(_ id: UUID) {
        undoLogID = nil
        Task {
            do {
                try await health.deleteFoodEntry(id: id)
                showToast("Removed ✓")
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                showToast("Couldn't undo: \(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ message: String, clearsUndo: Bool = false) {
        toast = message
        Task {
            // Leave the undo toast up longer so it's actually reachable.
            try? await Task.sleep(for: .seconds(clearsUndo ? 5 : 2))
            if toast == message {
                toast = nil
                if clearsUndo { undoLogID = nil }
            }
        }
    }
}

/// The deliberate tap target for logging — a small rice-paper capsule so a
/// stray row tap can't log by accident.
private struct LogButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.ricePaper, in: .capsule)
        }
        // .borderless keeps the tap target isolated inside the List row —
        // other styles let a stray row tap trigger the button.
        .buttonStyle(.borderless)
        .accessibilityLabel("Log \(name)")
    }
}

struct LibraryRow: View {
    let name: String
    let detail: String
    let kcal: Double
    let sodiumMg: Double
    var isFavorite = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(name)
                        .foregroundStyle(.primary)
                }
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
