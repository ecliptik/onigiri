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
    @State private var isLogging = false
    @State private var pendingMealDeletes: [Meal] = []
    @State private var pendingFoodDeletes: [Food] = []
    @State private var searchText = ""
    @State private var categoryFilter: FoodCategory?
    @State private var portionTarget: PortionTarget?
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var formPrefill: ProductPrefill?

    /// Favorites first, then items whose category matches the current meal
    /// slot (breakfast in the morning, dinner in the evening…), then name.
    private static func ranked(
        _ lhs: (isFavorite: Bool, category: String?, name: String),
        _ rhs: (isFavorite: Bool, category: String?, name: String)
    ) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        let slot = FoodCategory.slot(for: .now).rawValue
        let lhsNow = lhs.category == slot
        let rhsNow = rhs.category == slot
        if lhsNow != rhsNow { return lhsNow }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private var filteredMeals: [Meal] {
        meals
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { Self.ranked(($0.isFavorite, $0.category, $0.name), ($1.isFavorite, $1.category, $1.name)) }
    }

    private var filteredFoods: [Food] {
        foods
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { Self.ranked(($0.isFavorite, $0.category, $0.name), ($1.isFavorite, $1.category, $1.name)) }
    }

    private func matches(name: String, category: String?) -> Bool {
        if let filter = categoryFilter, category != filter.rawValue { return false }
        if searchText.isEmpty { return true }
        if name.localizedCaseInsensitiveContains(searchText) { return true }
        // Matching the category text too lets "snack" pull up all snacks.
        return category?.localizedCaseInsensitiveContains(searchText) ?? false
    }

    var body: some View {
        // Bound once per evaluation: each access to the computed properties
        // re-filters and re-sorts the whole library (~3× per keystroke).
        let visibleMeals = filteredMeals
        let visibleFoods = filteredFoods
        NavigationStack {
            List {
                if !visibleMeals.isEmpty {
                    Section("Meals") {
                        ForEach(visibleMeals) { meal in
                            HStack(spacing: 10) {
                                LibraryRow(
                                    name: meal.name,
                                    detail: meal.items.compactMap(\.food?.name).joined(separator: ", "),
                                    kcal: meal.totalKcal,
                                    sodiumMg: meal.totalSodiumMg,
                                    isFavorite: meal.isFavorite
                                )
                                // Meals stay one-tap: their category rides
                                // along; long-press still offers portions.
                                LogButton(name: meal.name) {
                                    log(name: meal.name, kcal: meal.totalKcal,
                                        sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                                        category: PortionTarget.category(from: meal.category))
                                } onCustomPortion: {
                                    portionTarget = PortionTarget(
                                        name: meal.name, kcal: meal.totalKcal,
                                        sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                                        serving: "1 meal",
                                        defaultCategory: PortionTarget.category(from: meal.category)
                                    )
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { editingMeal = meal }
                            // No row contextMenu: its long-press recognizer
                            // would swallow the Log button's portion gesture.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingMeal = meal
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.riceToast)
                                Button {
                                    meal.isFavorite.toggle()
                                    PhoneSyncService.shared.push(from: context)
                                } label: {
                                    Label("Favorite", systemImage: meal.isFavorite ? "star.slash" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                            // Explicit trailing action (not .onDelete) so
                            // the reveal shows the same trash icon as the
                            // Today log's swipe — one delete look app-wide.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingMealDeletes = [meal]
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }

                Section("Foods") {
                    ForEach(visibleFoods) { food in
                        HStack(spacing: 10) {
                            LibraryRow(
                                name: food.name,
                                detail: food.servingDescription,
                                kcal: food.kcal,
                                sodiumMg: food.sodiumMg,
                                isFavorite: food.isFavorite
                            )
                            // Foods always confirm through the portion sheet
                            // so the serving and meal slot are deliberate.
                            LogButton(name: food.name) {
                                portionTarget = makePortionTarget(for: food)
                            } onCustomPortion: {
                                portionTarget = makePortionTarget(for: food)
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture { editingFood = food }
                        // No row contextMenu: its long-press recognizer
                        // would swallow the Log button's portion gesture.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingFood = food
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.riceToast)
                            Button {
                                food.isFavorite.toggle()
                                PhoneSyncService.shared.push(from: context)
                            } label: {
                                Label("Favorite", systemImage: food.isFavorite ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingFoodDeletes = [food]
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }

                    if foods.isEmpty {
                        ContentUnavailableView(
                            "No foods yet",
                            systemImage: "fork.knife",
                            description: Text("Add a food once — calories and sodium off the label — then log it any day with a tap.")
                        )
                    } else if visibleFoods.isEmpty && visibleMeals.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }

                // Saved items always rank first; the online database is one
                // more section below — a quick log/add without the food form.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: searchText, search: onlineSearch) { product in
                        // Known barcodes log fast; new foods go through the
                        // full prefilled form (Save / Save & Log).
                        if let existing = foods.first(where: { $0.barcode == product.barcode }) {
                            portionTarget = makePortionTarget(for: existing)
                        } else {
                            formPrefill = ProductPrefill(product: product)
                        }
                    }
                }
            }
            .compactSections()
            .navigationTitle("Foods")
            .searchable(text: $searchText, prompt: "Search foods, meals, and online")
            .onSubmit(of: .search) {
                Task { await onlineSearch.search(searchText) }
            }
            .onChange(of: searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    onlineSearch.clear()
                }
            }
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
                        // "＋ Add" instead of a bare plus: reads as a
                        // general add that opens choices.
                        Label("Add", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Add food or meal")
                }
            }
            .sheet(isPresented: $showNewFood) { FoodFormView(food: nil) }
            .sheet(item: $formPrefill) { prefill in
                FoodFormView(food: nil, prefill: prefill.product)
            }
            .sheet(isPresented: $showScanFood) { FoodFormView(food: nil, startScanning: true) }
            .sheet(item: $editingFood) { FoodFormView(food: $0) }
            .sheet(isPresented: $showNewMeal) { MealFormView() }
            .sheet(item: $editingMeal) { MealFormView(meal: $0) }
            .sheet(item: $portionTarget) { target in
                PortionSheet(target: target) { quantity, category in
                    log(name: target.name, kcal: target.kcal,
                        sodiumMg: target.sodiumMg, nutrients: target.nutrients,
                        category: category, quantity: quantity)
                }
                .presentationDetents([.medium, .large])
            }
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
            .confirmationDialog(
                deleteMealsTitle,
                isPresented: .init(
                    get: { !pendingMealDeletes.isEmpty },
                    set: { if !$0 { pendingMealDeletes = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    pendingMealDeletes.forEach(context.delete)
                    pendingMealDeletes = []
                    PhoneSyncService.shared.push(from: context)
                }
            }
            .confirmationDialog(
                deleteFoodsTitle,
                isPresented: .init(
                    get: { !pendingFoodDeletes.isEmpty },
                    set: { if !$0 { pendingFoodDeletes = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    pendingFoodDeletes.forEach(context.delete)
                    pendingFoodDeletes = []
                    // Drop the now food-less items from any meals that
                    // used the deleted foods.
                    LibraryMaintenance.repairDanglingFoodReferences(context: context)
                    PhoneSyncService.shared.push(from: context)
                }
            }
        }
    }

    private var deleteMealsTitle: String {
        pendingMealDeletes.count == 1
            ? "Delete “\(pendingMealDeletes[0].name)”?"
            : "Delete \(pendingMealDeletes.count) meals?"
    }

    private var deleteFoodsTitle: String {
        let base = pendingFoodDeletes.count == 1
            ? "Delete “\(pendingFoodDeletes[0].name)”?"
            : "Delete \(pendingFoodDeletes.count) foods?"
        let foodIDs = Set(pendingFoodDeletes.map(\.persistentModelID))
        let affectedMeals = Set(meals.filter { meal in
            meal.items.contains { item in
                item.food.map { foodIDs.contains($0.persistentModelID) } ?? false
            }
        }.map(\.name))
        guard !affectedMeals.isEmpty else { return base }
        return base + " It will also be removed from \(affectedMeals.sorted().joined(separator: ", "))."
    }

    private func makePortionTarget(for food: Food) -> PortionTarget {
        PortionTarget(
            name: food.name, kcal: food.kcal,
            sodiumMg: food.sodiumMg, nutrients: food.nutrients,
            serving: food.servingDescription,
            defaultCategory: PortionTarget.category(from: food.category)
        )
    }

    private func log(
        name: String, kcal: Double, sodiumMg: Double,
        nutrients: NutrientValues, category: FoodCategory, quantity: Double = 1
    ) {
        // The log keeps the plain food name; the portion only scales values.
        guard !isLogging else { return }
        isLogging = true
        Task {
            defer { isLogging = false }
            await LogActions.logFood(
                name: name,
                kcal: kcal * quantity,
                sodiumMg: sodiumMg * quantity,
                nutrients: nutrients.scaled(by: quantity),
                category: category
            )
        }
    }
}

/// Portion helpers shared by the quick menu and the custom sheet.
enum Portion {
    static let quickOptions: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2]

    static func label(for quantity: Double) -> String {
        switch quantity {
        case 0.25: "¼"
        case 0.5: "½"
        case 0.75: "¾"
        case 1.5: "1½"
        default: quantity.formatted(.number.precision(.fractionLength(0...2)))
        }
    }
}

/// What the custom-portion sheet is scaling, and which meal slot it
/// defaults to (the item's own category, else the current time of day).
struct PortionTarget: Identifiable {
    var id: String { name }
    let name: String
    let kcal: Double
    let sodiumMg: Double
    let nutrients: NutrientValues
    let serving: String
    var defaultCategory: FoodCategory = .slot(for: .now)

    static func category(from stored: String?) -> FoodCategory {
        stored.flatMap(FoodCategory.init(rawValue:)) ?? .slot(for: .now)
    }
}

/// The deliberate tap target for logging — a small rice-paper capsule so a
/// stray row tap can't log by accident. Shared by the Foods list and the
/// quick-log sheet: rows tap to edit, this button logs.
struct LogButton: View {
    let name: String
    let action: () -> Void
    let onCustomPortion: () -> Void

    var body: some View {
        Image(systemName: "plus")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.riceToast)
            .padding(8)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay(
                Circle().strokeBorder(Color.riceToast.opacity(0.5), lineWidth: 1)
            )
            // The long-press affordance, reachable without the gesture.
            .accessibilityAction(named: "Custom portion") { onCustomPortion() }
            // HIG minimum touch target; the visible circle stays small.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .onTapGesture { action() }
            .onLongPressGesture(minimumDuration: 0.4) { onCustomPortion() }
            .accessibilityLabel("Log \(name)")
            .accessibilityAddTraits(.isButton)
    }
}

/// Pick a portion and meal slot with a live preview before logging.
struct PortionSheet: View {
    let target: PortionTarget
    let onLog: (Double, FoodCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = 1.0
    @State private var category: FoodCategory

    init(target: PortionTarget, onLog: @escaping (Double, FoodCategory) -> Void) {
        self.target = target
        self.onLog = onLog
        _category = State(initialValue: target.defaultCategory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(target.name) {
                    HStack {
                        ForEach(Portion.quickOptions, id: \.self) { option in
                            Button(Portion.label(for: option)) {
                                quantity = option
                            }
                            .buttonStyle(.bordered)
                            .tint(quantity == option ? .riceToast : .secondary)
                        }
                    }
                    LabeledContent("Servings") {
                        TextField("1", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if !target.serving.isEmpty {
                        LabeledContent("One serving") {
                            Text(target.serving)
                        }
                    }
                }
                Section {
                    Picker("Meal", selection: $category) {
                        ForEach(FoodCategory.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Will log") {
                        Text("\(target.kcal * quantity, format: .number.precision(.fractionLength(0))) kcal • \(target.sodiumMg * quantity, format: .number.precision(.fractionLength(0))) mg Na")
                            .monospacedDigit()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        onLog(quantity, category)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(quantity <= 0)
                }
            }
        }
    }
}

struct LibraryRow: View {
    let name: String
    let detail: String
    let kcal: Double
    let sodiumMg: Double
    var isFavorite = false
    /// Shown where meals and foods share one list (the Log sheet) —
    /// the Foods tab's sections already say which is which.
    var isMeal = false

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
                    if isMeal {
                        Text("Meal")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.6), in: .capsule)
                    }
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
