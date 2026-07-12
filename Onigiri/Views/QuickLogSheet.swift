import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// One-stop logging from the Today screen: favorites up top, search below,
/// tap a row to log it and dismiss. Long-press a row for portions.
struct QuickLogSheet: View {
    var initialKind: QuickActions.QuickLogKind = .all
    /// Timestamp for the entries this sheet logs — Today passes the browsed
    /// day so past days can be backfilled.
    var logDate: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var kind: QuickActions.QuickLogKind = .all
    @State private var kindLoaded = false
    @State private var searchText = ""
    @State private var isLogging = false
    @State private var portionTarget: PortionTarget?
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var showScanner = false
    @State private var isLookingUpBarcode = false
    @State private var formPrefill: ProductPrefill?
    @State private var editingFood: Food?
    @State private var editingMeal: Meal?
    @State private var showLibraryImporter = false
    /// Last week's distinct logged foods, newest first (HealthKit history).
    @State private var recents: [FoodLogEntry] = []

    private struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        let isFavorite: Bool
        let category: String?
        var food: Food?
        var meal: Meal?
        var isMeal: Bool { meal != nil }
    }

    private var allItems: [Item] {
        let mealItems = meals.map { meal in
            Item(
                id: "meal-\(meal.uuid.uuidString)",
                name: meal.name,
                detail: "",
                kcal: meal.totalKcal,
                sodiumMg: meal.totalSodiumMg,
                nutrients: meal.totalNutrients,
                isFavorite: meal.isFavorite,
                category: meal.category,
                meal: meal
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
                category: food.category,
                food: food
            )
        }
        return mealItems + foodItems
    }

    /// Takes the item list as a parameter so body computes the whole
    /// allItems → filtered → favorites/others chain once per evaluation
    /// instead of ~3× per keystroke through chained computed properties.
    private func filtered(_ items: [Item]) -> [Item] {
        let matched = items.filter { item in
            switch kind {
            case .meals: if !item.isMeal { return false }
            case .foods: if item.isMeal { return false }
            case .all: break
            }
            if searchText.isEmpty { return true }
            if item.name.localizedCaseInsensitiveContains(searchText) { return true }
            return item.category?.localizedCaseInsensitiveContains(searchText) ?? false
        }
        // Favorites first, then items matching the current meal slot, then name.
        let slot = FoodCategory.slot(for: .now).rawValue
        return matched.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            let lhsNow = lhs.category == slot
            let rhsNow = rhs.category == slot
            if lhsNow != rhsNow { return lhsNow }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// A history entry is "a meal" when its name still matches the meal
    /// library — drives the Meal tag and the kind filter for Recents.
    private func isMealName(_ name: String) -> Bool {
        meals.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        let items = allItems
        let visible = filtered(items)
        let favorites = visible.filter(\.isFavorite)
        let others = visible.filter { !$0.isFavorite }
        // Recents respect the Meals/Foods filter like everything else.
        let visibleRecents = recents.filter { entry in
            switch kind {
            case .all: true
            case .meals: isMealName(entry.name)
            case .foods: !isMealName(entry.name)
            }
        }
        NavigationStack {
            List {
                // Segmented controls don't scale with Dynamic Type (UIKit
                // limitation) — at accessibility sizes this becomes a menu
                // row so the labels grow with everything else.
                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Show", selection: $kind) {
                        Text("All").tag(QuickActions.QuickLogKind.all)
                        Text("Meals").tag(QuickActions.QuickLogKind.meals)
                        Text("Foods").tag(QuickActions.QuickLogKind.foods)
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker("Show", selection: $kind) {
                        Text("All").tag(QuickActions.QuickLogKind.all)
                        Text("Meals").tag(QuickActions.QuickLogKind.meals)
                        Text("Foods").tag(QuickActions.QuickLogKind.foods)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if isLookingUpBarcode {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking up product…")
                            .foregroundStyle(.secondary)
                    }
                }
                // What you actually ate lately beats any sort order — but it
                // yields to search, which is about finding something else.
                if searchText.isEmpty, !visibleRecents.isEmpty {
                    Section("Recent") {
                        ForEach(visibleRecents) { entry in
                            recentRow(entry)
                        }
                    }
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
                    if visible.isEmpty {
                        // Accurate copy: this sheet can create foods itself
                        // via the scan button and online search above.
                        if items.isEmpty {
                            ContentUnavailableView {
                                Label("No saved foods yet", systemImage: "fork.knife")
                            } description: {
                                Text("Scan a barcode or search online above — logged foods are saved for next time.\n\nOr bring your library from another device: export it there (Settings → Export library) and import the file here.")
                            } actions: {
                                // Text-only: with a systemImage, iOS 26
                                // collapses the label to a bare icon here.
                                Button("Import library…") {
                                    showLibraryImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            ContentUnavailableView(
                                "No matches",
                                systemImage: "magnifyingglass",
                                description: Text("Try different words, or search online below.")
                            )
                        }
                    }
                }

                // Saved items rank first; the online database follows so a
                // one-off food can be logged without saving it.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: searchText, search: onlineSearch, onPick: { product in
                        route(product)
                    }, onAddManually: { name in
                        formPrefill = ProductPrefill(product: ScannedProduct(
                            barcode: "", name: name, kcal: nil, sodiumMg: nil,
                            servingDescription: "", nutrients: NutrientValues()
                        ))
                    })
                }
            }
            .compactSections()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            // A/B variant: system search field (focus animation, cancel,
            // scroll-away) with the barcode scanner in the toolbar.
            .searchable(text: $searchText, prompt: "Search library and online")
            .onSubmit(of: .search) {
                Task { await onlineSearch.search(searchText) }
            }
            .onChange(of: searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    onlineSearch.clear()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")
                }
            }
            .task {
                if !kindLoaded {
                    kindLoaded = true
                    kind = initialKind
                }
                recents = (try? await HealthKitService().recentFoodEntries()) ?? []
            }
            .sheet(item: $portionTarget) { target in
                PortionSheet(target: target) { quantity, category in
                    log(
                        Item(id: target.name, name: target.name, detail: target.serving,
                             kcal: target.kcal, sodiumMg: target.sodiumMg,
                             nutrients: target.nutrients, isFavorite: false, category: nil),
                        quantity: quantity,
                        category: category
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { code in
                    lookUpBarcode(code)
                }
            }
            .sheet(item: $formPrefill) { prefill in
                // New foods go through the full form — reviewable, complete,
                // and saved to the library. Its Log action finishes the log.
                FoodFormView(food: nil, prefill: prefill.product, logDate: logDate) {
                    dismiss()
                }
            }
            .sheet(item: $editingFood) { FoodFormView(food: $0) }
            .sheet(item: $editingMeal) { MealFormView(meal: $0) }
            .fileImporter(isPresented: $showLibraryImporter, allowedContentTypes: [.json]) { result in
                ToastCenter.shared.show(LibraryTransfer.handlePickedFile(result, context: context))
            }
        }
        .toastHost()
    }

    /// The fast portion sheet for a barcode the library already knows.
    private func libraryTarget(forBarcode code: String) -> PortionTarget? {
        guard let existing = foods.first(where: { $0.barcode == code }) else { return nil }
        return PortionTarget(
            name: existing.name,
            kcal: existing.kcal,
            sodiumMg: existing.sodiumMg,
            nutrients: existing.nutrients,
            serving: existing.servingDescription,
            defaultCategory: PortionTarget.category(from: existing.category)
        )
    }

    /// A known barcode goes straight to the fast portion sheet; anything
    /// new opens the prefilled food form.
    private func route(_ product: ScannedProduct) {
        if let target = libraryTarget(forBarcode: product.barcode) {
            portionTarget = target
        } else {
            formPrefill = ProductPrefill(product: product)
        }
    }

    /// Scan → library check → fetch the product if it's new. The network
    /// fetch also gives the scanner sheet time to finish dismissing before
    /// the next sheet presents.
    private func lookUpBarcode(_ code: String) {
        if let target = libraryTarget(forBarcode: code) {
            portionTarget = target
            return
        }
        isLookingUpBarcode = true
        Task {
            defer { isLookingUpBarcode = false }
            do {
                let product = try await OpenFoodFactsClient().product(barcode: code)
                formPrefill = ProductPrefill(product: product)
            } catch {
                // Transient failures toast, like everything else; the
                // sheet has its own toastHost (the root's renders behind
                // presented sheets).
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    /// Same semantics as the Foods list: tapping the row opens the editor;
    /// the + capsule logs (meals one-tap, foods confirm the portion).
    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            LibraryRow(
                name: item.name,
                detail: item.detail,
                kcal: item.kcal,
                sodiumMg: item.sodiumMg,
                isFavorite: item.isFavorite,
                isMeal: item.isMeal
            )
            LogButton(name: item.name) {
                if item.isMeal {
                    log(item, quantity: 1, category: PortionTarget.category(from: item.category))
                } else {
                    portionTarget = makePortionTarget(for: item)
                }
            } onCustomPortion: {
                portionTarget = makePortionTarget(for: item)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if let meal = item.meal {
                editingMeal = meal
            } else if let food = item.food {
                editingFood = food
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    /// A recent entry re-logs through the portion sheet. No editor behind
    /// the row — there's nothing to edit — so the whole row is the action.
    private func recentRow(_ entry: FoodLogEntry) -> some View {
        HStack(spacing: 10) {
            LibraryRow(
                name: entry.name,
                detail: entry.date.formatted(.relative(presentation: .named)),
                kcal: entry.kcal,
                sodiumMg: entry.sodiumMg,
                // History entries don't know what they were; a name still
                // in the meal library is the best available signal.
                isMeal: isMealName(entry.name)
            )
            LogButton(name: entry.name) {
                portionTarget = recentTarget(for: entry)
            } onCustomPortion: {
                portionTarget = recentTarget(for: entry)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            portionTarget = recentTarget(for: entry)
        }
        .accessibilityAddTraits(.isButton)
    }

    /// Library values win when a food of the same name still exists —
    /// they carry Micheal's hand-corrections. Otherwise re-log the
    /// entry's own values.
    private func recentTarget(for entry: FoodLogEntry) -> PortionTarget {
        if let food = foods.first(where: {
            $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame
        }) {
            return PortionTarget(
                name: food.name, kcal: food.kcal, sodiumMg: food.sodiumMg,
                nutrients: food.nutrients, serving: food.servingDescription,
                defaultCategory: PortionTarget.category(from: food.category)
            )
        }
        return PortionTarget(
            name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
            nutrients: entry.nutrients, serving: "as last logged",
            defaultCategory: entry.category
        )
    }

    private func makePortionTarget(for item: Item) -> PortionTarget {
        PortionTarget(
            name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
            nutrients: item.nutrients, serving: item.detail,
            defaultCategory: PortionTarget.category(from: item.category)
        )
    }

    private func log(_ item: Item, quantity: Double, category: FoodCategory) {
        guard !isLogging else { return }
        isLogging = true
        Task {
            let logged = await LogActions.logFood(
                name: item.name,
                kcal: item.kcal * quantity,
                sodiumMg: item.sodiumMg * quantity,
                nutrients: item.nutrients.scaled(by: quantity),
                category: category,
                date: logDate
            )
            if logged {
                dismiss()
            } else {
                isLogging = false
            }
        }
    }
}

#Preview {
    QuickLogSheet()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
