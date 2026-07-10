import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// One-stop logging from the Today screen: favorites up top, search below,
/// tap a row to log it and dismiss. Long-press a row for portions.
struct QuickLogSheet: View {
    var initialKind: QuickActions.QuickLogKind = .all

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var kind: QuickActions.QuickLogKind = .all
    @State private var kindLoaded = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isLogging = false
    @State private var portionTarget: PortionTarget?
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var showScanner = false
    @State private var isLookingUpBarcode = false
    @State private var formPrefill: ProductPrefill?

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
        var isMeal = false
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
                category: meal.category,
                isMeal: true
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

    private var favorites: [Item] {
        filtered.filter(\.isFavorite)
    }

    private var others: [Item] {
        filtered.filter { !$0.isFavorite }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $kind) {
                    Text("All").tag(QuickActions.QuickLogKind.all)
                    Text("Meals").tag(QuickActions.QuickLogKind.meals)
                    Text("Foods").tag(QuickActions.QuickLogKind.foods)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // A plain field instead of .searchable so the barcode
                // scanner can sit inside the row, at its right edge.
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search library and online", text: $searchText)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await onlineSearch.search(searchText) }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear search")
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundStyle(Color.riceToast)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Scan barcode")
                }

                if isLookingUpBarcode {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking up product…")
                            .foregroundStyle(.secondary)
                    }
                }
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

                // Saved items rank first; the online database follows so a
                // one-off food can be logged without saving it.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: searchText, search: onlineSearch) { product in
                        route(product)
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    onlineSearch.clear()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if !kindLoaded {
                    kindLoaded = true
                    kind = initialKind
                }
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
                // and saved to the library. Save & Log finishes the log.
                FoodFormView(food: nil, prefill: prefill.product) {
                    dismiss()
                }
            }
        }
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
        errorMessage = nil
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
                errorMessage = error.localizedDescription
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
            // Meals log one-tap with their category; foods confirm the
            // portion and meal slot in the sheet.
            if item.isMeal {
                log(item, quantity: 1, category: PortionTarget.category(from: item.category))
            } else {
                portionTarget = makePortionTarget(for: item)
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            portionTarget = makePortionTarget(for: item)
        }
        .accessibilityAddTraits(.isButton)
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
            do {
                try await health.logFood(
                    name: item.name,
                    kcal: item.kcal * quantity,
                    sodiumMg: item.sodiumMg * quantity,
                    nutrients: item.nutrients.scaled(by: quantity),
                    category: category
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
