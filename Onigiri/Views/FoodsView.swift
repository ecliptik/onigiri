import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// The library: saved foods and one-tap meals. Rows tap to edit; the +
/// capsule logs (foods through the portion sheet, meals one-tap).
/// Structured like the Log sheet (1.8.1): a Foods/Meals/Favorites scope
/// bar on top, a Scan Barcode row beneath it, search at the bottom on
/// iOS 26, filterable by category, favorites floating to the top.
struct FoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]

    /// What the list shows — the Log sheet's scopes (its .all/.scan are
    /// routing kinds, not scopes, so they have no counterpart here).
    private enum Scope: String, CaseIterable {
        // Declaration order IS segment order: Favorites leads (the
        // user — the starred shortlist should be the easiest reach).
        case favorites = "Favorites", foods = "Foods", meals = "Meals"
    }

    /// One sheet slot (the QuickLogSheet pattern): the six chained
    /// .sheet modifiers this view used to carry compete with each
    /// other, and the scanner→portion handoff sets the next sheet
    /// while the scanner is still dismissing — with separate slots
    /// that presentation could silently fail, eating the scan.
    private enum ActiveSheet: Identifiable {
        case newFood
        case newMeal
        case form(ProductPrefill)
        case editFood(Food)
        case editMeal(Meal)
        case portion(PortionTarget)
        case scanner

        var id: String {
            switch self {
            case .newFood: "newFood"
            case .newMeal: "newMeal"
            case .form(let prefill): "form-\(prefill.id)"
            case .editFood(let food): "editFood-\(food.persistentModelID.hashValue)"
            case .editMeal(let meal): "editMeal-\(meal.uuid.uuidString)"
            case .portion(let target): "portion-\(target.name)"
            case .scanner: "scanner"
            }
        }
    }

    /// A favorites-scope row: meals and foods mixed in one ranked list,
    /// like the Log sheet's Favorites.
    private enum FavoriteEntry: Identifiable {
        case meal(Meal)
        case food(Food)

        var id: String {
            switch self {
            case .meal(let meal): "meal-\(meal.uuid.uuidString)"
            case .food(let food): "food-\(food.persistentModelID.hashValue)"
            }
        }
        var recency: Date {
            switch self {
            case .meal(let meal): meal.recencyDate
            case .food(let food): food.recencyDate
            }
        }
        var name: String {
            switch self {
            case .meal(let meal): meal.name
            case .food(let food): food.name
            }
        }
    }

    // Favorites lead (the user, 2026-07-14 — supersedes the Foods
    // default picked a day earlier).
    @State private var scope: Scope = .favorites
    @State private var activeSheet: ActiveSheet?
    @State private var showAddChooser = false
    @State private var quickActions = QuickActions.shared
    @State private var isLogging = false
    @State private var isLookingUpBarcode = false
    @State private var pendingMealDeletes: [Meal] = []
    @State private var pendingFoodDeletes: [Food] = []
    @State private var searchText = ""
    @State private var categoryFilter: FoodCategory?
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var showLibraryImporter = false
    /// The list order, remembered (the user liked the meal builder's
    /// sort menu). Default = the favorites-first blend.
    @AppStorage("foodsLibrarySort") private var sortRaw = LibrarySort.ranked.rawValue

    enum LibrarySort: String, CaseIterable {
        case ranked, recent, name

        var label: String {
            switch self {
            case .ranked: "Favorites first"
            case .recent: "Recent"
            case .name: "Name"
            }
        }
    }

    private var librarySort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .ranked }

    /// Favorites first, then by recency (last logged, falling back to
    /// when it was added — the user: recent beats slot affinity), then
    /// name for stability. The sort menu can flatten this to plain
    /// recency or alphabetical.
    private func ranked(
        _ lhs: (isFavorite: Bool, recency: Date, name: String),
        _ rhs: (isFavorite: Bool, recency: Date, name: String)
    ) -> Bool {
        switch librarySort {
        case .ranked:
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        case .recent:
            if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        case .name:
            break
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private var filteredMeals: [Meal] {
        meals
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { ranked(($0.isFavorite, $0.recencyDate, $0.name), ($1.isFavorite, $1.recencyDate, $1.name)) }
    }

    private var filteredFoods: [Food] {
        foods
            .filter { matches(name: $0.name, category: $0.category) }
            .sorted { ranked(($0.isFavorite, $0.recencyDate, $0.name), ($1.isFavorite, $1.recencyDate, $1.name)) }
    }

    private func matches(name: String, category: String?) -> Bool {
        if let filter = categoryFilter, category != filter.rawValue { return false }
        if searchText.isEmpty { return true }
        if name.localizedCaseInsensitiveContains(searchText) { return true }
        // Matching the category text too lets "snack" pull up all snacks.
        return category?.localizedCaseInsensitiveContains(searchText) ?? false
    }

    /// The Favorites scope pool: everybody here is starred, so rank by
    /// recency alone (then name), matching the Log sheet — unless the
    /// sort menu asked for names.
    private func favoriteEntries(meals: [Meal], foods: [Food]) -> [FavoriteEntry] {
        let entries = meals.filter(\.isFavorite).map(FavoriteEntry.meal)
            + foods.filter(\.isFavorite).map(FavoriteEntry.food)
        return entries.sorted { lhs, rhs in
            if librarySort != .name, lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        // Bound once per evaluation: each access to the computed properties
        // re-filters and re-sorts the whole library (~3× per keystroke).
        let visibleMeals = filteredMeals
        let visibleFoods = filteredFoods
        NavigationStack {
            List {
                // The scope picker rides IN the list, not a pinned
                // safeAreaInset: any top inset suppresses large-title
                // rendering (screenshot-verified twice — blank title
                // zone with both drawer modes), and matching the other
                // tabs' large leading title won (the user). At rest the
                // screen reads the same; the picker just scrolls.
                Section {
                    ScopeBar(
                        options: Scope.allCases.map { ($0.rawValue, $0) },
                        selection: $scope
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                // The scan entry, a labeled row like the new-food form's
                // (not a toolbar icon — roadmap 1.8.1). Hidden while
                // searching so results lead, and on the Meals scope —
                // scanning adds a FOOD; meals are built from foods
                // already added (the user).
                if searchText.isEmpty, scope != .meals {
                    Section {
                        Button {
                            activeSheet = .scanner
                        } label: {
                            ScanRowLabel()
                        }
                        .disabled(isLookingUpBarcode)
                        if isLookingUpBarcode {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Looking up product…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                switch scope {
                case .foods:
                    Section {
                        ForEach(visibleFoods) { food in
                            foodRow(food)
                        }
                        emptyState(visibleCount: visibleFoods.count)
                    }
                case .meals:
                    Section {
                        ForEach(visibleMeals) { meal in
                            mealRow(meal)
                        }
                        emptyState(visibleCount: visibleMeals.count)
                    }
                case .favorites:
                    let favorites = favoriteEntries(meals: visibleMeals, foods: visibleFoods)
                    Section {
                        ForEach(favorites) { entry in
                            switch entry {
                            case .meal(let meal): mealRow(meal, badged: true)
                            case .food(let food): foodRow(food)
                            }
                        }
                        emptyState(visibleCount: favorites.count)
                    }
                }

                // Saved items always rank first; the online database is one
                // more section below — a quick log/add without the food form.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: searchText, search: onlineSearch, onPick: { product in
                        // Known barcodes log fast; new foods go through the
                        // full prefilled form (Save / Save & Log).
                        if let existing = foods.first(where: { $0.barcode == product.barcode }) {
                            activeSheet = .portion(makePortionTarget(for: existing))
                        } else {
                            activeSheet = .form(ProductPrefill(product: product))
                        }
                    }, onAddManually: { name in
                        activeSheet = .form(ProductPrefill(product: ScannedProduct(
                            barcode: "", name: name, kcal: nil, sodiumMg: nil,
                            servingDescription: "", nutrients: NutrientValues()
                        )))
                    })
                }
            }
            .compactSections()
            .hardTopScrollEdge()
            .readableContentWidth(groupedBackground: true)
            .expandsTabBarAtTop()
            .navigationTitle("Foods")
            .fileImporter(isPresented: $showLibraryImporter, allowedContentTypes: [.json]) { result in
                ToastCenter.shared.show(LibraryTransfer.handlePickedFile(result, context: context))
            }
            // The STANDARD system search field, top drawer BY PLATFORM:
            // 1.8.1 wanted it at the bottom like the Log sheet's, and
            // DefaultToolbarItem(kind: .search, placement: .bottomBar)
            // was tried (2026-07-13) — with the corner Add pill occupying
            // the search-tab slot, the system renders the field BEHIND
            // the floating tab bar (untappable) and drops the large
            // title. Bottom search in a TabView belongs to the search
            // tab; ours is the Add pill, by ruling. iOS 18 is the same
            // drawer either way.
            // displayMode .always: with the pinned scope bar's
            // safeAreaInset below it, the default hide-on-scroll drawer
            // re-expands BLANK after a scroll — element present, field
            // invisible (screenshot-verified 2026-07-13, the second
            // drawer-desync after the old GeometryReader one). Pinning
            // the drawer skips the collapse/re-expand cycle entirely.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Foods, Meals, and More"
            )
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
                            // The fill/unfill swap morphs instead of
                            // hard-cutting (iOS 17 API, floor-safe).
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortRaw) {
                            ForEach(LibrarySort.allCases, id: \.rawValue) { option in
                                Text(option.label).tag(option.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: librarySort == .ranked
                              ? "arrow.up.arrow.down.circle"
                              : "arrow.up.arrow.down.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel("Sort")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .newFood:
                    FoodFormView(food: nil)
                case .newMeal:
                    MealFormView()
                case .form(let prefill):
                    FoodFormView(food: nil, prefill: prefill.product)
                case .editFood(let food):
                    FoodFormView(food: food)
                case .editMeal(let meal):
                    MealFormView(meal: meal)
                case .portion(let target):
                    PortionSheet(target: target) { quantity, category, _ in
                        log(name: target.name, kcal: target.kcal,
                            sodiumMg: target.sodiumMg, nutrients: target.nutrients,
                            category: category, quantity: quantity)
                    }
                    .presentationDetents([.medium, .large])
                case .scanner:
                    // A parsed label takes the unknown-barcode route: the
                    // single sheet slot re-presents as the prefilled food
                    // form. Deferred one turn — the sheet dismisses itself
                    // right after this closure, and a synchronous swap
                    // gets torn down by that dismissal.
                    ScanSheet(onCode: { code in
                        lookUpBarcode(code)
                    }, onLabel: { parsed in
                        let prefill = ProductPrefill(product: parsed.scannedProduct())
                        Task { activeSheet = .form(prefill) }
                    })
                }
            }
            // The corner + while on this tab (the toolbar "+ Add" menu
            // consolidated into it): a Food-or-Meal chooser. Consumable
            // Optional, checked on change and appear (the Bool-flag
            // version of this pattern goes dead).
            .onChange(of: quickActions.addFoodRequest) { _, _ in
                consumeAddFoodRequest()
            }
            .onAppear { consumeAddFoodRequest() }
            // A centered ALERT, the app's standard dialog — the
            // confirmationDialog rendered as an anchored bubble up by
            // the tab bar (the iOS 26 quote-popover look the user keeps
            // vetoing). Background layer: two alerts already chain on
            // this view.
            .background {
                Color.clear.alert("Add to your library", isPresented: $showAddChooser) {
                    Button("Add Food") { activeSheet = .newFood }
                    if !foods.isEmpty {
                        Button("Add Meal") { activeSheet = .newMeal }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            // Alerts, not confirmationDialogs: iOS 26 anchors dialogs to
            // the source row as a popover bubble; a destructive confirm
            // should be the standard centered alert.
            .alert(
                deleteMealsTitle,
                isPresented: .init(
                    get: { !pendingMealDeletes.isEmpty },
                    set: { if !$0 { pendingMealDeletes = [] } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    pendingMealDeletes.forEach(context.delete)
                    pendingMealDeletes = []
                    PhoneSyncService.shared.push(from: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .alert(
                deleteFoodsTitle,
                isPresented: .init(
                    get: { !pendingFoodDeletes.isEmpty },
                    set: { if !$0 { pendingFoodDeletes = [] } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    pendingFoodDeletes.forEach(context.delete)
                    pendingFoodDeletes = []
                    // Drop the now food-less items from any meals that
                    // used the deleted foods.
                    LibraryMaintenance.repairDanglingFoodReferences(context: context)
                    PhoneSyncService.shared.push(from: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteFoodsMessage)
            }
        }
    }

    /// A meal row: name + totals, one-tap log, long-press for portions.
    /// `badged` marks it "Meal" where the list mixes types (Favorites).
    private func mealRow(_ meal: Meal, badged: Bool = false) -> some View {
        HStack(spacing: 10) {
            // Just the meal's name — listing every member made rows
            // balloon (the user).
            LibraryRow(
                name: meal.name,
                detail: "",
                kcal: meal.totalKcal,
                sodiumMg: meal.totalSodiumMg,
                isFavorite: meal.isFavorite,
                isMeal: badged
            )
            // Meals stay one-tap: their category rides along;
            // long-press still offers portions.
            LogButton(name: meal.name) {
                meal.lastUsedAt = .now
                log(name: meal.name, kcal: meal.totalKcal,
                    sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                    category: PortionTarget.category(from: meal.category))
            } onLongPress: {
                meal.lastUsedAt = .now
                activeSheet = .portion(PortionTarget(
                    name: meal.name, kcal: meal.totalKcal,
                    sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                    serving: "1 meal",
                    defaultCategory: PortionTarget.category(from: meal.category)
                ))
            }
        }
        .contentShape(.rect)
        .onTapGesture { activeSheet = .editMeal(meal) }
        // Role + named action, like the Log sheet's rows — the tap-to-edit
        // is otherwise invisible to VoiceOver. NOT combined: the + capsule
        // must stay its own element (the water-row lesson).
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit") { activeSheet = .editMeal(meal) }
        // No row contextMenu: its long-press recognizer would swallow
        // the Log button's portion gesture.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                activeSheet = .editMeal(meal)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.riceToast)
            Button {
                meal.isFavorite.toggle()
                // A light tap: the neighboring delete confirms loudly,
                // this was silent.
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                PhoneSyncService.shared.push(from: context)
            } label: {
                Label("Favorite", systemImage: meal.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        // Explicit trailing action (not .onDelete) so the reveal shows
        // the same trash icon as the Today log's swipe — one delete
        // look app-wide.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingMealDeletes = [meal]
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            // The screen-wide riceToast tint bleeds into destructive
            // swipe pills on iOS 26.
            .tint(.red)
        }
    }

    /// A food row: tap the + for the portion sheet (serving and meal
    /// slot stay deliberate); long press skips it and logs the default
    /// portion — the fast path when the label serving is the serving.
    private func foodRow(_ food: Food) -> some View {
        HStack(spacing: 10) {
            LibraryRow(
                name: food.name,
                detail: food.servingDescription,
                kcal: food.kcal,
                sodiumMg: food.sodiumMg,
                isFavorite: food.isFavorite
            )
            LogButton(name: food.name, longPressName: "Log default portion") {
                food.lastUsedAt = .now
                activeSheet = .portion(makePortionTarget(for: food))
            } onLongPress: {
                food.lastUsedAt = .now
                log(name: food.name, kcal: food.kcal,
                    sodiumMg: food.sodiumMg, nutrients: food.nutrients,
                    category: PortionTarget.category(from: food.category))
            }
        }
        .contentShape(.rect)
        .onTapGesture { activeSheet = .editFood(food) }
        // Role + named action, like the Log sheet's rows (see mealRow).
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit") { activeSheet = .editFood(food) }
        // No row contextMenu: its long-press recognizer would swallow
        // the Log button's portion gesture.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                activeSheet = .editFood(food)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.riceToast)
            Button {
                food.isFavorite.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            .tint(.red)
        }
    }

    /// Scope-aware empty states, rendered inside the list section.
    @ViewBuilder
    private func emptyState(visibleCount: Int) -> some View {
        if visibleCount == 0 {
            if scope == .foods && foods.isEmpty {
                ContentUnavailableView {
                    Label("No saved foods yet", systemImage: "fork.knife")
                } description: {
                    Text("Add a food once — calories and nutrients off the label, then log it with a tap.\n\nAlready tracking on another device? Export its library (Settings → Export Library), save the file, and import it here.")
                } actions: {
                    // Text-only: with a systemImage, iOS 26 collapses
                    // the label to a bare icon here (as in toolbars).
                    Button {
                        showLibraryImporter = true
                    } label: {
                        Text("Import Library…")
                            // Dark-on-cream: the inherited riceToast tint
                            // put a white label at ~1.9:1 in dark mode.
                            .foregroundStyle(Color.onRicePaper)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ricePaper)
                }
            } else if !searchText.isEmpty {
                // Compact on purpose, NOT ContentUnavailableView (the
                // Log sheet's lesson): its full-height layout shoves the
                // Online section's search button under the search bar.
                VStack(spacing: 4) {
                    Text("No matches")
                        .font(.headline)
                    Text("Try different words, or search online below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if scope == .meals && meals.isEmpty {
                Text("No saved meals yet — tap + to build one from saved foods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if scope == .favorites {
                Text("No favorites yet — swipe right on a food or meal to star it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Items exist but the category filter excluded them all.
                Text("Nothing in this category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func consumeAddFoodRequest() {
        guard quickActions.addFoodRequest != nil else { return }
        quickActions.addFoodRequest = nil
        showAddChooser = true
    }

    /// Scan → library check → fetch the product if it's new. Routing
    /// matches this screen's online-search picks: a known barcode opens
    /// the fast portion sheet, a new one the prefilled food form. The
    /// single sheet slot re-presents on the item change, so the handoff
    /// from the dismissing scanner can't be eaten.
    private func lookUpBarcode(_ code: String) {
        if let existing = foods.first(where: { $0.barcode == code }) {
            existing.lastUsedAt = .now
            activeSheet = .portion(makePortionTarget(for: existing))
            return
        }
        isLookingUpBarcode = true
        Task {
            defer { isLookingUpBarcode = false }
            do {
                let product = try await OpenFoodFactsClient().product(barcode: code)
                activeSheet = .form(ProductPrefill(product: product))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private var deleteMealsTitle: String {
        pendingMealDeletes.count == 1
            ? "Delete “\(pendingMealDeletes[0].name)”?"
            : "Delete \(pendingMealDeletes.count) meals?"
    }

    private var deleteFoodsTitle: String {
        pendingFoodDeletes.count == 1
            ? "Delete “\(pendingFoodDeletes[0].name)”?"
            : "Delete \(pendingFoodDeletes.count) foods?"
    }

    private var deleteFoodsMessage: String {
        let foodIDs = Set(pendingFoodDeletes.map(\.persistentModelID))
        let affectedMeals = Set(meals.filter { meal in
            meal.items.contains { item in
                item.food.map { foodIDs.contains($0.persistentModelID) } ?? false
            }
        }.map(\.name))
        guard !affectedMeals.isEmpty else { return "This can't be undone." }
        return "It will also be removed from \(affectedMeals.sorted().joined(separator: ", ")). This can't be undone."
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
// (The fraction-glyph servings format lived here briefly; the user
// prefers plain decimals — 0.85 of a serving fine-tunes calories in a
// way ¾ never could.)

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

/// ONE scan row, one camera behind it (the user's copy) — barcode fires
/// live, the shutter photographs the label. Leading icon drawn with
/// LogButton's exact circle treatment (same font, padding, fill, rim)
/// so the row carries the same visual weight as the + capsules beside
/// it (the user). Shared by the Foods tab and the Log sheet.
struct ScanRowLabel: View {
    var body: some View {
        Label {
            Text("Scan Barcode or Nutrition Label")
        } icon: {
            Image(systemName: "barcode.viewfinder")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.riceToast)
                // FIXED frame, not padding: the barcode glyph is wider
                // than the plus, so equal padding drew a bigger circle.
                // 35pt matches LogButton's RENDERED circle (the plus
                // glyph is narrower than its font's full height, so its
                // glyph+9pt padding lands at ~35, not 39 — measured).
                .frame(width: 35, height: 35)
                .background(.quaternary.opacity(0.5), in: .circle)
                .overlay(
                    Circle().strokeBorder(Color.riceToast.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

/// The deliberate tap target for logging — a small rice-paper capsule so a
/// stray row tap can't log by accident. Shared by the Foods list and the
/// quick-log sheet: rows tap to edit, this button logs.
struct LogButton: View {
    let name: String
    /// What the long press does, for the a11y action — "Custom portion"
    /// on meal rows, "Log default portion" on food rows (each type's
    /// long press is the OTHER type's tap).
    var longPressName = "Custom portion"
    let action: () -> Void
    /// nil = tap-only (the water row: one gesture, one meaning).
    var onLongPress: (() -> Void)?

    /// Drives the tap bounce — the visual twin of the haptic.
    @State private var bounce = false

    var body: some View {
        // Body-size glyph in a ~39 pt circle: proportional to the rows
        // (the subheadline circle read undersized, title3 too chunky —
        // the user tried both) while staying inside the 44 pt frame
        // below, so row heights don't move.
        let circle = Image(systemName: "plus")
            .font(.body.weight(.bold))
            .symbolEffect(.bounce, value: bounce)
            .foregroundStyle(Color.riceToast)
            .padding(9)
            // A static fill, NOT glassEffect: a live glass layer on
            // every list row made Foods stutter on scroll.
            .background(.quaternary.opacity(0.5), in: .circle)
            .overlay(
                Circle().strokeBorder(Color.riceToast.opacity(0.5), lineWidth: 1)
            )
            // HIG minimum touch target; the visible circle stays small.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .onTapGesture {
                bounce.toggle()
                action()
            }
            .accessibilityLabel("Log \(name)")
            .accessibilityAddTraits(.isButton)
        if let onLongPress {
            circle
                // The long-press affordance, reachable without the gesture.
                .accessibilityAction(named: longPressName) { onLongPress() }
                .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
        } else {
            circle
        }
    }
}

/// Pick a portion and meal slot with a live preview before logging.
/// With `editDate` set (the log row's Edit) it also offers the entry's
/// date and time, passed back as the closure's third value.
struct PortionSheet: View {
    let target: PortionTarget
    let editDate: Date?
    let onLog: (Double, FoodCategory, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var quantity = 1.0
    @State private var category: FoodCategory
    @State private var entryDate: Date
    @FocusState private var quantityFocused: Bool

    init(
        target: PortionTarget,
        editDate: Date? = nil,
        onLog: @escaping (Double, FoodCategory, Date?) -> Void
    ) {
        self.target = target
        self.editDate = editDate
        self.onLog = onLog
        _category = State(initialValue: target.defaultCategory)
        _entryDate = State(initialValue: editDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(target.name) {
                    // Plain decimals, 0.01–100: type 0.85 to fine-tune
                    // calories, or 2 to double. The ± buttons step by
                    // quarters for quick nudges.
                    Stepper(value: $quantity, in: 0.01...100, step: 0.25) {
                        LabeledContent("Serving") {
                            // The field bypasses the Stepper's range, so
                            // clamp here too: an absurd typed quantity
                            // (1e18) logs kcal that overflow the Int
                            // casts in row labels and crash-loop Today.
                            TextField("1", value: Binding(
                                get: { quantity },
                                set: { quantity = min(max($0, 0.01), 100) }
                            ), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                .focused($quantityFocused)
                        }
                        .padding(.trailing, 8)
                    }
                    if !target.serving.isEmpty {
                        LabeledContent("One serving") {
                            Text(target.serving)
                        }
                    }
                }
                Section {
                    // Segmented controls ignore Dynamic Type; go menu at
                    // accessibility sizes so the slot names scale too.
                    if dynamicTypeSize.isAccessibilitySize {
                        Picker("Meal", selection: $category) {
                            ForEach(FoodCategory.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("Meal", selection: $category) {
                            ForEach(FoodCategory.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    LabeledContent("Will log") {
                        Text("\(target.kcal * quantity, format: .number.precision(.fractionLength(0))) kcal • \(target.sodiumMg * quantity, format: .number.precision(.fractionLength(0))) mg Na")
                            .monospacedDigit()
                    }
                }
                // Edit mode only: move the entry in time ("logged at
                // 11 pm but it was yesterday's dinner" used to mean
                // delete + re-log).
                if editDate != nil {
                    Section {
                        DatePicker(
                            "Time",
                            selection: $entryDate,
                            in: ...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Select-all on focus, like the food form: the prefilled "1"
            // is usually replaced, not appended to. This sheet has one
            // text field and no sub-sheets, so no scoping guards needed.
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )) { note in
                guard let field = note.object as? UITextField else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editDate != nil ? "Save" : "Log") {
                        // TextField(value:format:) commits on focus
                        // resignation — resign, then read the quantity
                        // a runloop later, or a typed 0.5 logs as 1.
                        quantityFocused = false
                        DispatchQueue.main.async {
                            onLog(
                                min(max(quantity, 0.01), 100),
                                category,
                                editDate != nil ? entryDate : nil
                            )
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(quantity <= 0)
                }
                // Decimal pads have no return key; surface a Done while
                // editing, like the food form.
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
        }
        // Frosted, not flat: stacked over the food form (or the Log
        // sheet) the default background blends into the sheet behind —
        // in dark mode only the grabber separated them. The material,
        // a larger corner radius, and a hairline rim make it read as a
        // physically separate card in both modes.
        .presentationCornerRadius(28)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.thickMaterial)
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
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
    /// Shown where meals and foods share one list (the Log sheet, the
    /// Favorites scope) — the Foods/Meals scopes already say which is
    /// which.
    var isMeal = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var nameLine: some View {
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
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Side-by-side columns squeeze names into mid-word breaks at
            // accessibility sizes — stack the row instead.
            VStack(alignment: .leading, spacing: 4) {
                nameLine
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal · \(sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                nameLine
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
