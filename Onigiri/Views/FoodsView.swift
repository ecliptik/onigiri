import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// The library: saved foods and one-tap meals. Rows tap to edit; the +
/// capsule logs (foods through the portion sheet, meals one-tap).
/// Structured like the Log sheet (1.8.1): a Foods/Meals/Favorites scope
/// bar on top, search at the bottom on iOS 26, filterable by category,
/// favorites floating to the top. The entry doors that used to sit
/// under the scope bar moved out entirely (2026-08-02) — see the note
/// in `body`.
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
    /// other, and a handoff that sets the next sheet while the current
    /// one is still dismissing could silently fail with separate slots,
    /// eating the pick.
    private enum ActiveSheet: Identifiable {
        case newFood
        case newMeal
        case form(ProductPrefill)
        case editFood(Food)
        case editMeal(Meal)
        case portion(PortionTarget)

        var id: String {
            switch self {
            case .newFood: "newFood"
            case .newMeal: "newMeal"
            case .form(let prefill): "form-\(prefill.id)"
            case .editFood(let food): "editFood-\(food.persistentModelID.hashValue)"
            case .editMeal(let meal): "editMeal-\(meal.uuid.uuidString)"
            case .portion(let target): "portion-\(target.name)"
            }
        }
    }

    /// A row in a list that MIXES types: the Favorites scope, and every
    /// grouped search result. (Was `FavoriteEntry` — the cross-scope
    /// search needs the same mixed row, and two near-identical wrappers
    /// would drift.)
    private enum LibraryEntry: Identifiable, LibrarySearchable {
        case meal(Meal)
        case food(Food)

        var id: String {
            switch self {
            case .meal(let meal): "meal-\(meal.uuid.uuidString)"
            case .food(let food): "food-\(food.persistentModelID.hashValue)"
            }
        }

        /// Food and Meal each conform in the kit; this just forwards,
        /// so the enum can never disagree with the models about what a
        /// name or a star is.
        private var model: any LibrarySearchable {
            switch self {
            case .meal(let meal): meal
            case .food(let food): food
            }
        }
        var searchName: String { model.searchName }
        var searchCategory: String? { model.searchCategory }
        var isStarred: Bool { model.isStarred }
        var isMealRow: Bool { model.isMealRow }
        /// The Foods tab shows the LIBRARY; HealthKit history rows are
        /// the Log sheet's business.
        var isHistoryRow: Bool { false }
        var searchRecency: Date { model.searchRecency }
    }

    /// Which scope opens first. Favorites led from 2026-07-14; the user
    /// asked for Foods on 2026-08-05. It is a SETTING now rather than a
    /// third hardcoded reversal — Appearance → "Foods tab opens on".
    /// Segment order is unchanged (Favorites still reads first in the
    /// bar); only the initial selection follows this.
    @AppStorage(SharedStore.foodsDefaultScopeKey, store: SharedStore.defaults)
    private var defaultScopeRaw = Scope.foods.rawValue
    /// nil until the user picks one THIS session, so the setting decides
    /// the opening scope without stamping over a live choice on every
    /// re-appear (which an onAppear assignment would do).
    @State private var scope: Scope?
    private var currentScope: Scope {
        scope ?? Scope(rawValue: defaultScopeRaw) ?? .foods
    }
    private var scopeBinding: Binding<Scope> {
        Binding(get: { currentScope }, set: { scope = $0 })
    }
    @State private var activeSheet: ActiveSheet?
    @State private var quickActions = QuickActions.shared
    @State private var isLogging = false
    @State private var pendingMealDeletes: [Meal] = []
    @State private var pendingFoodDeletes: [Food] = []
    @State private var searchText = ""
    @State private var categoryFilter: FoodCategory?
    @State private var showLibraryImporter = false
    /// The list order, remembered (the user liked the meal builder's
    /// sort menu). Default = Recent; the Favorites SCOPE owns the
    /// starred shortlist (its sort twin was removed 2026-07-19).
    @AppStorage("foodsLibrarySort") private var sortRaw = LibrarySort.recent.rawValue
    // The secondary row metric follows the first tracked slot (the
    // user: sodium was hardcoded; now it customizes with Settings).
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var libraryMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }

    private var librarySort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    /// Recency first (last logged, falling back to when it was added —
    /// the user: recent beats slot affinity), then name for stability;
    /// the sort menu can flatten to alphabetical.
    private func ranked(
        _ lhs: (isFavorite: Bool, recency: Date, name: String),
        _ rhs: (isFavorite: Bool, recency: Date, name: String)
    ) -> Bool {
        LibrarySearch.isOrderedBefore(
            (lhs.recency, lhs.name), (rhs.recency, rhs.name),
            byRecency: librarySort == .recent
        )
    }

    private var filteredMeals: [Meal] {
        meals
            .filter { matches($0) }
            .sorted { ranked(($0.isFavorite, $0.recencyDate, $0.name), ($1.isFavorite, $1.recencyDate, $1.name)) }
    }

    private var filteredFoods: [Food] {
        foods
            .filter { matches($0) }
            .sorted { ranked(($0.isFavorite, $0.recencyDate, $0.name), ($1.isFavorite, $1.recencyDate, $1.name)) }
    }

    /// The toolbar's category FILTER (a browsing constraint) plus the
    /// query. The query half is the kit's rule — name or category text,
    /// so "snack" still pulls up all snacks — shared with the Log sheet
    /// so the two fields can't answer differently.
    private func matches(_ item: some LibrarySearchable) -> Bool {
        inSelectedCategory(item) && LibrarySearch.matches(item, query: searchText)
    }

    /// The CATEGORY half of `matches`, on its own.
    ///
    /// The search path needs it without the query, because
    /// `LibrarySearch.groups` applies the query itself — feeding it
    /// `matches`-filtered rows ran the same predicate and the same sort
    /// twice per keystroke (audit, 2026-08-17). It has to stay a
    /// separate step rather than passing the raw arrays through: the
    /// category picker lives in the toolbar and is reachable WHILE
    /// searching, so dropping it here would quietly widen a filtered
    /// search back out to the whole library.
    private func inSelectedCategory(_ item: some LibrarySearchable) -> Bool {
        guard let filter = categoryFilter else { return true }
        return item.searchCategory == filter.rawValue
    }

    /// The Favorites scope pool: everybody here is starred, so rank by
    /// recency alone (then name), matching the Log sheet — unless the
    /// sort menu asked for names. Routed through the shared grouper so
    /// the starred-first precedence and the ranking have ONE definition.
    private func favoriteEntries(meals: [Meal], foods: [Food]) -> [LibraryEntry] {
        let entries = meals.map(LibraryEntry.meal) + foods.map(LibraryEntry.food)
        return LibrarySearch
            .groups(entries, query: "", sortByRecency: librarySort != .name)
            .first { $0.group == .favorites }?.items ?? []
    }

    /// A query crosses every scope and groups the matches; the scope
    /// bar is a browsing control, not a search filter.
    private func searchGroups(
        meals: [Meal], foods: [Food]
    ) -> [(group: LibrarySearchGroup, items: [LibraryEntry])] {
        let entries = meals.map(LibraryEntry.meal) + foods.map(LibraryEntry.food)
        return LibrarySearch.groups(entries, query: searchText, sortByRecency: librarySort != .name)
    }

    var body: some View {
        // Bound once per evaluation: each access to the computed properties
        // re-filters and re-sorts the whole library (~3× per keystroke).
        let visibleMeals = filteredMeals
        let visibleFoods = filteredFoods
        // ONE search-active predicate: the scope bar, the estimate row,
        // and which list shape renders all have to agree.
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        // Category-filtered but NOT query-filtered: the grouper does the
        // query, so handing it `visibleMeals`/`visibleFoods` filtered and
        // sorted it a second time for the same answer.
        let groups = searching
            ? searchGroups(
                meals: meals.filter { inSelectedCategory($0) },
                foods: foods.filter { inSelectedCategory($0) }
            )
            : []
        NavigationStack {
            List {
                // The scope picker rides IN the list, not a pinned
                // safeAreaInset: any top inset suppresses large-title
                // rendering (screenshot-verified twice — blank title
                // zone with both drawer modes), and matching the other
                // tabs' large leading title won (the user). At rest the
                // screen reads the same; the picker just scrolls.
                // Hidden while searching: a query crosses every scope,
                // so a highlighted segment would contradict the groups
                // below it. (A list ROW here, not the sheet's
                // safeAreaInset — an `if` is safe.)
                if !searching {
                    Section {
                        ScopeBar(
                            options: Scope.allCases.map { ($0.rawValue, $0) },
                            selection: scopeBinding
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                // The entry doors used to lead this list. They're gone
                // (the user, 2026-08-02): this is the LIBRARY screen,
                // and the + already opens an Add Food form that carries
                // the very same two doors — so the screen shipped two
                // add paths competing for the same job, with the actual
                // library pushed below them. The doors now live only
                // where adding is what you came to do: Add Food, and
                // the Log sheet (which keeps the scan → known barcode →
                // portion shortcut, since logging is that path's point).
                // Scanning a new food is one tap longer and the library
                // leads with the library.
                //
                // **This search is LOCAL ONLY** (2026-08-30, the user:
                // "so it only searches added/saved foods and meals").
                // The tap-to-estimate row and the online database used
                // to lead here too, mirroring the Log sheet before its
                // own describe field took them over — but Foods already
                // has a door for AI/online/manual/photo one tap away
                // (Add Food), so this field asks a narrower, truer
                // question: what's already IN my library. A query that
                // finds nothing here now points there instead of
                // opening a second, competing route to the same finds.
                if searching {
                    // Favorites → Foods → Meals, one home per row (a
                    // starred food is under Favorites and NOT again
                    // under Foods), empty groups dropped.
                    ForEach(groups, id: \.group) { group in
                        Section(group.group.rawValue) {
                            ForEach(group.items) { entry in
                                switch entry {
                                // The meal mark only where the group
                                // MIXES types; the Meals header already
                                // says it otherwise.
                                case .meal(let meal):
                                    mealRow(meal)
                                case .food(let food):
                                    foodRow(food)
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Section {
                            emptyState(visibleCount: 0)
                        }
                    }
                } else {
                    switch currentScope {
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
                                case .meal(let meal): mealRow(meal)
                                case .food(let food): foodRow(food)
                                }
                            }
                            emptyState(visibleCount: favorites.count)
                        }
                    }
                }
            }
            .compactSections()
            .hardTopScrollEdge()
            .readableContentWidth(groupedBackground: true)
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
            // LOCAL library search only (2026-08-30) — the prompt
            // dropped "and More" along with the online/AI sections that
            // word was covering for; Add Food carries those now.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Foods and Meals"
            )
            .toolbar {
                // Filter + sort on the trailing edge, matching Today and
                // Calendar: the leading ~20pt is iOS's back-swipe zone, which
                // intermittently steals taps from a control placed there
                // (v2.5.10). The title holds the left; nothing tappable sits
                // in the edge gesture's path.
                ToolbarItemGroup(placement: .topBarTrailing) {
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
                    Menu {
                        Picker("Sort", selection: $sortRaw) {
                            ForEach(LibrarySort.allCases, id: \.rawValue) { option in
                                Text(option.label).tag(option.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: librarySort == .recent
                              ? "arrow.up.arrow.down.circle"
                              : "arrow.up.arrow.down.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel("Sort")
                }
            }
            // The corner + while on this tab (the toolbar "+ Add" menu
            // consolidated into it): a Food-or-Meal chooser. Consumable
            // Optional, checked on change and appear (the Bool-flag
            // version of this pattern goes dead).
            // The add chooser now lives in ContentView (so it survives the
            // +'s search-tab bounce); it routes the pick here as addFoodKind.
            // Consumable Optional, checked on change AND appear — a stuck
            // flag never re-fires onChange.
            .onChange(of: quickActions.addFoodKind) { _, _ in
                consumeAddFoodKind()
            }
            .onAppear { consumeAddFoodKind() }
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
                    // Explicit save (GoalUpsert's discipline) — see FoodFormView.
                    context.saveOrReport("Couldn't delete those meals")
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
                    // Explicit save (GoalUpsert's discipline) — see FoodFormView.
                    context.saveOrReport("Couldn't delete those foods")
                    PhoneSyncService.shared.push(from: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteFoodsMessage)
            }
        }
        // On the NavigationStack, NOT the searchable List: presenting a
        // sheet over the search drawer's view leaves the drawer's search
        // controller unable to take focus after the dismissal — taps
        // land, the keyboard never rises (iOS 26, reproduced by
        // testFoodsSearchAfterSave after any form save).
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newFood:
                FoodFormView(food: nil)
            case .newMeal:
                MealFormView()
            case .form(let prefill):
                FoodFormView(food: nil, prefill: prefill.product, prefillMessage: prefill.provenance)
            case .editFood(let food):
                FoodFormView(food: food)
            case .editMeal(let meal):
                MealFormView(meal: meal)
            case .portion(let target):
                PortionSheet(target: target) { quantity, category, _ in
                    // Only reached on confirm — a cancelled sheet never
                    // runs this, which is exactly why the recency bump
                    // belongs here and not at present time.
                    markUsed(target.source)
                    log(name: target.name, kcal: target.kcal,
                        sodiumMg: target.sodiumMg, nutrients: target.nutrients,
                        category: category, quantity: quantity,
                        mealItems: target.mealItems)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// A meal row: name + totals, one-tap log, long-press for portions.
    ///
    /// Always carries the meal mark. It used to be conditional
    /// (`badged`), on the theory that the Meals scope's own header
    /// already says what these are — but that made a meal look like one
    /// thing in Foods → Meals and another in Favorites, in search
    /// results, and in the Log sheet, which marks them unconditionally.
    /// A row should read the same wherever it appears (the user,
    /// 2026-08-14).
    /// Equatable gate for a library row: any @Query write (one favorite
    /// toggle, one form save) re-runs this whole screen's body, and
    /// without the gate every visible row re-built its buttons and
    /// swipe actions for it (audit, 2026-08-17 — FoodLogRow's rule in
    /// TodayView, extended to the library). `content` runs only when
    /// what the row RENDERS changed.
    private struct EquatableLibraryRow<Content: View>: View, Equatable {
        let name: String
        let detail: String
        let kcal: Double
        let metric: TrackedNutrient
        let metricAmount: Double
        let isFavorite: Bool
        let aiGenerated: Bool
        @ViewBuilder let content: () -> Content

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name && lhs.detail == rhs.detail
                && lhs.kcal == rhs.kcal && lhs.metric == rhs.metric
                && lhs.metricAmount == rhs.metricAmount
                && lhs.isFavorite == rhs.isFavorite
                && lhs.aiGenerated == rhs.aiGenerated
        }

        var body: some View { content() }
    }

    private func mealRow(_ meal: Meal) -> some View {
        EquatableLibraryRow(
            name: meal.name, detail: "", kcal: meal.totalKcal,
            metric: libraryMetric,
            metricAmount: libraryMetric.itemAmount(
                sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients) ?? 0,
            isFavorite: meal.isFavorite, aiGenerated: meal.aiGenerated
        ) {
            mealRowBody(meal)
        }
        .equatable()
    }

    private func mealRowBody(_ meal: Meal) -> some View {
        HStack(spacing: 10) {
            // Just the meal's name — listing every member made rows
            // balloon (the user).
            LibraryRow(
                name: meal.name,
                detail: "",
                kcal: meal.totalKcal,
                metric: libraryMetric,
                metricAmount: libraryMetric.itemAmount(
                    sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients) ?? 0,
                isFavorite: meal.isFavorite,
                isMeal: true,
                aiGenerated: meal.aiGenerated
            )
            // Meals stay one-tap: their category rides along;
            // long-press still offers portions.
            LogButton(name: meal.name) {
                markUsed(meal)
                log(name: meal.name, kcal: meal.totalKcal,
                    sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                    category: PortionTarget.category(from: meal.category),
                    aiGenerated: meal.aiGenerated,
                    mealItems: meal.loggedItems)
            } onLongPress: {
                // No recency bump here: this only OPENS the portion
                // sheet. Its confirm handler stamps `source`.
                activeSheet = .portion(PortionTarget(
                    name: meal.name, kcal: meal.totalKcal,
                    sodiumMg: meal.totalSodiumMg, nutrients: meal.totalNutrients,
                    serving: "1 meal",
                    defaultCategory: PortionTarget.category(from: meal.category),
                    aiGenerated: meal.aiGenerated,
                    mealItems: meal.loggedItems,
                    source: meal.persistentModelID
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
                context.saveOrLog("meal favorite")
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
        EquatableLibraryRow(
            name: food.name, detail: food.servingDescription, kcal: food.kcal,
            metric: libraryMetric,
            metricAmount: libraryMetric.itemAmount(
                sodiumMg: food.sodiumMg, nutrients: food.nutrients) ?? 0,
            isFavorite: food.isFavorite, aiGenerated: food.aiGenerated
        ) {
            foodRowBody(food)
        }
        .equatable()
    }

    private func foodRowBody(_ food: Food) -> some View {
        HStack(spacing: 10) {
            LibraryRow(
                name: food.name,
                detail: food.servingDescription,
                kcal: food.kcal,
                metric: libraryMetric,
                metricAmount: libraryMetric.itemAmount(
                    sodiumMg: food.sodiumMg, nutrients: food.nutrients) ?? 0,
                isFavorite: food.isFavorite,
                aiGenerated: food.aiGenerated
            )
            LogButton(name: food.name, longPressName: "Log default portion") {
                // Opens the portion sheet only — see `PortionTarget.source`.
                activeSheet = .portion(makePortionTarget(for: food))
            } onLongPress: {
                markUsed(food)
                log(name: food.name, kcal: food.kcal,
                    sodiumMg: food.sodiumMg, nutrients: food.nutrients,
                    category: PortionTarget.category(from: food.category),
                    aiGenerated: food.aiGenerated)
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
                context.saveOrLog("food favorite")
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
            if currentScope == .foods && foods.isEmpty {
                ContentUnavailableView {
                    Label("No saved foods yet", systemImage: "fork.knife")
                } description: {
                    // The migration paragraph that used to sit here
                    // explained the Import button rendered directly
                    // below it.
                    Text("Add a food once — calories and nutrients off the label, then log it with a tap.")
                } actions: {
                    // Text-only: with a systemImage, iOS 26 collapses
                    // the label to a bare icon here (as in toolbars).
                    Button {
                        showLibraryImporter = true
                    } label: {
                        Text("Import Food Library…")
                            // Dark-on-cream: the inherited riceToast tint
                            // put a white label at ~1.9:1 in dark mode.
                            .foregroundStyle(Color.onRicePaper)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ricePaper)
                }
            } else if !searchText.isEmpty {
                // Compact on purpose, NOT ContentUnavailableView (the
                // original Log-sheet lesson, still true even with no
                // Online section left to shove around).
                //
                // This search is LOCAL now (2026-08-30) — no online
                // fallback lives here any more, so the copy and the Add
                // Food button are UNCONDITIONAL regardless of the
                // lookups setting; the button still opens the full
                // form, which carries manual/photo/AI/online itself.
                // The privacy-default install (lookups off) must not
                // dead-end here — that was the original 2026-07-20 audit
                // HIGH this state exists to fix, and staying
                // unconditional keeps it fixed now that "online" isn't
                // this screen's decision to gate on any more.
                VStack(spacing: 4) {
                    Text("No matches")
                        .font(.headline)
                    Text("Try different words, or add it as a new food.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                Button {
                    activeSheet = .form(ProductPrefill(product: ScannedProduct(
                        barcode: "",
                        name: searchText.trimmingCharacters(in: .whitespaces),
                        kcal: nil, sodiumMg: nil,
                        servingDescription: "", nutrients: NutrientValues()
                    )))
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
            } else if currentScope == .meals && meals.isEmpty {
                Text("No saved meals yet — tap + to build one from saved foods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if currentScope == .favorites {
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

    private func consumeAddFoodKind() {
        guard let kind = quickActions.addFoodKind else { return }
        quickActions.addFoodKind = nil
        activeSheet = kind == .food ? .newFood : .newMeal
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
        let affectedMeals = LibraryReferences.mealNames(referencing: foodIDs, in: meals)
        guard !affectedMeals.isEmpty else { return "This can't be undone." }
        return "It will also be removed from \(affectedMeals.joined(separator: ", ")). This can't be undone."
    }

    /// Recency bump + explicit save: log taps are the app's most
    /// frequent SwiftData write, and autosave's crash window silently
    /// reverted Recent sort (2026-07-20 audit — the delete alerts got
    /// this discipline in v2.2.0, these sites never did).
    private func markUsed(_ food: Food) {
        food.lastUsedAt = .now
        context.saveOrLog("recency")
    }

    private func markUsed(_ meal: Meal) {
        meal.lastUsedAt = .now
        context.saveOrLog("recency")
    }

    /// The same bump, from a portion target that has come back through a
    /// sheet. Resolved against the loaded queries rather than
    /// `context.model(for:)`: an item deleted while the sheet was up
    /// simply isn't found, where a context lookup would hand back a
    /// fault whose first property access kills the process (the
    /// dangling-reference landmine).
    private func markUsed(_ id: PersistentIdentifier?) {
        guard let id else { return }
        if let food = foods.first(where: { $0.persistentModelID == id }) {
            markUsed(food)
        } else if let meal = meals.first(where: { $0.persistentModelID == id }) {
            markUsed(meal)
        }
    }

    private func makePortionTarget(for food: Food) -> PortionTarget {
        PortionTarget(
            name: food.name, kcal: food.kcal,
            sodiumMg: food.sodiumMg, nutrients: food.nutrients,
            serving: food.servingDescription,
            defaultCategory: PortionTarget.category(from: food.category),
            aiGenerated: food.aiGenerated,
            source: food.persistentModelID
        )
    }

    private func log(
        name: String, kcal: Double, sodiumMg: Double,
        nutrients: NutrientValues, category: FoodCategory, quantity: Double = 1,
        aiGenerated: Bool = false, mealItems: [LoggedMealItem] = []
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
                category: category,
                aiGenerated: aiGenerated,
                quantity: quantity,
                mealItems: mealItems
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
    /// AI-estimate provenance, carried into the log's metadata.
    var aiGenerated = false
    /// How many portions the target's values ALREADY represent — 1 for
    /// library items, the entry's stored quantity for history rows that
    /// re-log a multi-portion entry. The logged quantity metadata is
    /// the sheet's pick × this, so per-portion values stay recoverable.
    var baseQuantity: Double = 1
    /// Meal composition on the per-portion basis — drives the portion
    /// sheet's Contains section and rides into the log's metadata.
    /// Empty for plain foods.
    var mealItems: [LoggedMealItem] = []
    /// The library row this target came from, so recency can be stamped
    /// when the log actually HAPPENS instead of when the sheet opens.
    ///
    /// The bump used to fire at present time, because "the portion
    /// sheet's log path loses the model ref" — so opening a row to look
    /// at it, then backing out, still moved it to the top of Recent
    /// (the user, 2026-08-14). Recent means logged, not looked at.
    /// Carrying the identity is what makes that possible; nil for
    /// history re-logs and form logs, which have no library twin.
    var source: PersistentIdentifier?

    static func category(from stored: String?) -> FoodCategory {
        stored.flatMap(FoodCategory.init(rawValue:)) ?? .slot(for: .now)
    }
}

/// The scan door's row when Apple Intelligence is OFF — "Food" (the
/// identify cascade) only ever promised when it can be kept, so this
/// title drops it, unlike "Menu": a menu document is read by the
/// deterministic table parser, open with AI switched off either way.
/// With AI ON, `EntryDoorsSection` renders the compact camera button +
/// describe field instead (2026-08-29) — this row is what's left for
/// the AI-off case, so it no longer branches on
/// `FoodIntelligence.isAvailable` itself; its one caller only reaches
/// for it when that's already false.
///
/// Leading icon drawn with LogButton's exact circle treatment (same
/// font, padding, fill, rim) so the row carries the same visual weight
/// as the + capsules beside it (the user). Shared by the Foods tab and
/// the Log sheet.
struct ScanRowLabel: View {
    var body: some View {
        DoorRowLabel(
            title: "Scan Barcode, Label, or Menu",
            // A CAMERA, not a barcode (the user, 2026-08-02): the row
            // has read labels and identified food for two releases, and
            // the barcode glyph kept promising only the first of the
            // three. PLAIN camera, not camera.viewfinder (the user,
            // 2026-08-03): the viewfinder's brackets read as crowded
            // inside the circle this row draws — the circle is already
            // the frame, so a second one around the glyph is noise.
            systemImage: "camera")
    }
}

/// One entry door's row: title plus the circled leading glyph. Extracted
/// from ScanRowLabel when the paste and photo doors joined it
/// (PLAN-screenshot-nutrition) — the doors must read as siblings, and
/// three copies of the measured circle treatment would drift.
struct DoorRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            DoorCircleGlyph(systemImage: systemImage)
        }
    }
}

/// The circled glyph itself, split out of `DoorRowLabel` so the
/// icon-only camera button beside the describe field
/// (`EntryDoorsSection`, 2026-08-29) draws the SAME measured circle a
/// labeled door row does — one treatment, two callers, never two copies
/// to drift apart.
///
/// `diameter`/`font` default to the row's own 35pt/subheadline pairing;
/// `EntryDoorsSection`'s STANDALONE camera button — the only thing on
/// its side of the row, with no label beside it to lean on for weight —
/// passes the larger pairing instead (the user, 2026-08-29: "make the
/// camera button larger"). 44pt is Apple's own minimum tap target;
/// `.body.weight(.bold)` is LogButton's own glyph treatment at its
/// ~39pt circle, so scaling both up keeps the SAME proportions this
/// treatment was measured at rather than stretching a small glyph inside
/// a bigger ring.
struct DoorCircleGlyph: View {
    let systemImage: String
    var diameter: CGFloat = 35
    var font: Font = .subheadline.weight(.bold)

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(Color.riceToast)
            // FIXED frame, not padding: a viewfinder glyph is wider
            // than the plus, so equal padding drew a bigger circle.
            // 35pt matches LogButton's RENDERED circle (the plus
            // glyph is narrower than its font's full height, so its
            // glyph+9pt padding lands at ~35, not 39 — measured).
            .frame(width: diameter, height: diameter)
            // `.tertiarySystemGroupedBackground`, not `.quaternary`: the
            // hierarchical material is a VIBRANCY style, not a flat
            // color, and TodayView's own card background carries the
            // scar from finding this out ("quaternary-over-background
            // diverged in dark") — it renders fine in Simulator but
            // washes out light on a real device in dark mode (the
            // user, 2026-08-30, screenshot from-device: "light mode
            // button leak"). This is the one-nesting-level-in system
            // color for exactly this "chip inside a card" shape,
            // deterministic in both modes.
            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
            .overlay(
                Circle().strokeBorder(Color.riceToast.opacity(0.5), lineWidth: 1)
            )
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
            // every list row made Foods stutter on scroll. See
            // `DoorCircleGlyph` for why this is
            // `.tertiarySystemGroupedBackground` and not `.quaternary`
            // — the two are meant to render identically.
            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
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
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var portionMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @State private var quantity = 1.0
    @State private var category: FoodCategory
    @State private var entryDate: Date
    @FocusState private var quantityFocused: Bool
    /// Contains rows resolved to library foods, by row offset. A logged
    /// meal's parts are name+kcal SNAPSHOTS, so this is a name lookup —
    /// resolved once on appear, not per row render.
    @State private var resolvedFoods: [Int: Food] = [:]
    /// The library food this entry IS, when it's a plain food and still
    /// in the library — the door the log was missing.
    @State private var resolvedSelf: Food?
    /// The food a Contains row opened. PortionSheet's own single sheet
    /// slot: a nested sheet is fine, it's SWAPPING one slot's binding
    /// mid-dismissal that races (the 2026-07-22 landmine).
    @State private var openFood: Food?
    /// Guards the Save-to-Library row pair against a double tap while
    /// the write and dismiss are still in flight.
    @State private var isSavingToLibrary = false

    init(
        target: PortionTarget,
        editDate: Date? = nil,
        initialQuantity: Double = 1,
        onLog: @escaping (Double, FoodCategory, Date?) -> Void
    ) {
        self.target = target
        self.editDate = editDate
        self.onLog = onLog
        _quantity = State(initialValue: initialQuantity)
        _category = State(initialValue: target.defaultCategory)
        _entryDate = State(initialValue: editDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                    // A logged MEAL could always reach its foods through
                    // the Contains rows below; a logged FOOD had no door
                    // to its own library entry at all (the user,
                    // 2026-08-11). Same treatment as a Contains row: a
                    // real Button with a chevron, and shown only when the
                    // food is still findable — nothing to tap beats a tap
                    // that opens nothing.
                    if let food = resolvedSelf {
                        Button {
                            openFood = food
                        } label: {
                            HStack(spacing: 6) {
                                Text("View Food")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if target.mealItems.isEmpty, editDate != nil {
                        // The other half of "no door to its own library
                        // entry": a plain food that was LOGGED but never
                        // SAVED has no entry to view, but it can still be
                        // given one — from here, editing whichever past
                        // day it landed on, rather than re-scanning or
                        // re-searching it (the user, 2026-08-30: "go back
                        // to Friday on Sunday, then log/save that food to
                        // add to Sunday"). Two rows, not one, so saving
                        // alone stays possible — the app's Save / Save &
                        // Log pair (FoodFormView), in this sheet's own
                        // row-button shape rather than a toolbar pair,
                        // since the toolbar's trailing slot already belongs
                        // to this entry's own Save.
                        Button(action: saveToLibrary) {
                            Text("Save to Library").foregroundStyle(Color.riceToast)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingToLibrary)
                        Button(action: saveAndLogToday) {
                            Text("Save to Library & Log Today").foregroundStyle(Color.riceToast)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingToLibrary)
                    }
                } header: {
                    Text(target.name)
                } footer: {
                    // The same drift the Contains footer calls out, for
                    // the case that has no Contains section: this entry
                    // keeps the numbers it was logged with.
                    if resolvedSelf != nil, editDate != nil {
                        // Worded for what you might DO in there, not for
                        // the row's verb: the door says View, but the
                        // form behind it edits.
                        Text("Changes to the food apply to future logs, not this entry.")
                    } else if target.mealItems.isEmpty, editDate != nil {
                        Text("Uses the values above. \"Log Today\" adds a NEW entry for today — this one stays where it is.")
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
                        Text("\(target.kcal * quantity, format: .number.precision(.fractionLength(0))) kcal • \(portionMetric.captionText((portionMetric.itemAmount(sodiumMg: target.sodiumMg, nutrients: target.nutrients) ?? 0) * quantity, sodium: SharedStore.sodiumUnit))")
                            .monospacedDigit()
                    }
                    // Edit mode only: move the entry in time ("logged at
                    // 11 pm but it was yesterday's dinner" used to mean
                    // delete + re-log).
                    //
                    // Directly under Will log, beside the meal slot — the
                    // other two things an edit changes. It sat in its own
                    // section at the very BOTTOM, below a meal's Contains
                    // list, where it was missed entirely: the day was
                    // movable for releases and read as a feature the app
                    // did not have (the user, 2026-08-14).
                    if editDate != nil {
                        LogTimeRow(date: $entryDate)
                    }
                }
                // A logged/library MEAL explains its total: each
                // component's kcal share, live against the serving
                // stepper. Values are the log-time snapshot — the
                // library meal may have changed since.
                if !target.mealItems.isEmpty {
                    Section {
                        ForEach(Array(target.mealItems.enumerated()), id: \.offset) { offset, item in
                            containsRow(item, at: offset)
                        }
                    } header: {
                        Text("Contains")
                    } footer: {
                        // Snapshot vs entry drift (a kcal edit after
                        // logging changes the total, never the parts).
                        let partsKcal = target.mealItems.reduce(0) { $0 + $1.kcal }
                        if abs(partsKcal - target.kcal) > 1 {
                            Text("Values were edited after logging.")
                        }
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
        // Resolve once per presentation, not per row: an @Query here
        // would materialize the whole library and re-render the sheet on
        // any library change (the food form's checkForDuplicate lesson).
        .onAppear(perform: resolveContainsRows)
        // Opening the library food behind a Contains row. Editing it
        // changes the FOOD, not this already-logged entry — the section
        // footer already calls out that drift.
        .sheet(item: $openFood) { food in
            FoodFormView(food: food)
        }
        // Frosted, not flat: stacked over the food form (or the Log
        // sheet) the default background blends into the sheet behind —
        // in dark mode only the grabber separated them. The material,
        // a larger corner radius, and a hairline rim make it read as a
        // physically separate card in both modes. Shared chrome —
        // Style.swift's sheetCardChrome, one implementation with the
        // Edit Water sheet.
        .sheetCardChrome()
    }

    /// One Contains row. A row whose food is still in the library opens
    /// it — chevron, real Button (so VoiceOver announces and activates
    /// it). A row whose food was renamed or deleted stays plain text:
    /// nothing to tap beats a tap that opens nothing.
    @ViewBuilder
    private func containsRow(_ item: LoggedMealItem, at offset: Int) -> some View {
        let kcal = Text("\(item.kcal * quantity, format: .number.precision(.fractionLength(0))) kcal")
            .monospacedDigit()
        if let food = resolvedFoods[offset] {
            Button {
                openFood = food
            } label: {
                HStack(spacing: 6) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    kcal
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            LabeledContent(item.name) { kcal }
        }
    }

    /// Snapshot name → library food, once per presentation. The name
    /// carries its multiplier ("2× Egg", "1.5× Egg" locale-formatted), so
    /// that comes off before matching; matching itself is deliberately
    /// strict (ComponentMatch) — a wrong row would open the wrong food.
    private func resolveContainsRows() {
        // On-demand fetch, not an @Query: see the .onAppear note.
        let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        guard !foods.isEmpty else { return }
        let names = foods.map(\.name)
        // A plain food resolves ITSELF, by the same strict match the
        // Contains rows use. Meals are excluded deliberately: a meal's
        // name belongs to a Meal, and a Food that happened to share it
        // would open the wrong thing.
        if target.mealItems.isEmpty {
            if let index = ComponentMatch.index(of: target.name, in: names) {
                resolvedSelf = foods[index]
            }
            return
        }
        var resolved: [Int: Food] = [:]
        for (offset, item) in target.mealItems.enumerated() {
            let bare = ComponentMatch.strippingQuantityPrefix(item.name)
            if let index = ComponentMatch.index(of: bare, in: names) {
                resolved[offset] = foods[index]
            }
        }
        resolvedFoods = resolved
    }

    // MARK: Save to Library (a logged-but-unsaved history entry)

    /// This entry's PER-PORTION values, in the currency `MenuLibrarySave`
    /// already knows how to dedup and insert — the same path a picked
    /// menu row takes, so this can never mint a twin `LibraryDuplicate`
    /// wouldn't already catch. `quantity: 1`: the request's own quantity
    /// only matters for `saveToLibrary` in `MenuLogRequest`'s original
    /// caller (the describe-field flow); `MenuLibrarySave.insert` never
    /// reads it.
    private func libraryRequest() -> MenuLogRequest {
        var label = ParsedLabel()
        label.name = target.name
        label.kcal = target.kcal
        label.sodiumMg = target.sodiumMg
        label.nutrients = target.nutrients
        label.servingDescription = target.serving.isEmpty ? nil : target.serving
        label.aiGenerated = target.aiGenerated
        return MenuLogRequest(label: label, category: category, quantity: 1, saveToLibrary: true)
    }

    private func saveToLibrary() {
        guard !isSavingToLibrary else { return }
        isSavingToLibrary = true
        MenuLibrarySave.insert(libraryRequest(), into: context)
        ToastCenter.shared.show("Saved \(target.name) to your library ✓")
        dismiss()
    }

    /// Saves, then logs a SEPARATE new entry dated today — this entry,
    /// wherever it's dated, is untouched. Scaled by the sheet's own
    /// current Serving stepper, the same figure "Will log" already
    /// shows, so there is only ever one number on screen to read before
    /// tapping either button.
    private func saveAndLogToday() {
        guard !isSavingToLibrary else { return }
        isSavingToLibrary = true
        MenuLibrarySave.insert(libraryRequest(), into: context)
        Task {
            _ = await LogActions.logFood(
                name: target.name,
                kcal: target.kcal * quantity,
                sodiumMg: target.sodiumMg * quantity,
                nutrients: target.nutrients.scaled(by: quantity),
                category: category,
                aiGenerated: target.aiGenerated,
                quantity: quantity
            )
        }
        dismiss()
    }
}

struct LibraryRow: View {
    let name: String
    let detail: String
    let kcal: Double
    /// The secondary caption metric — the first tracked slot that
    /// applies to foods (sodium unless customized in Settings).
    let metric: TrackedNutrient
    let metricAmount: Double
    var isFavorite = false
    /// Marks a meal. Set for EVERY meal row, in every list — a scope
    /// header saying "Meals" is not a substitute, because it leaves the
    /// same meal looking like two different things depending on which
    /// list you found it in (the user, 2026-08-14).
    var isMeal = false
    /// AI-estimate provenance — a small ✨ after the name.
    var aiGenerated = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }
    // @AppStorage, not a static read — the Appearance picker's change
    // must repaint visible rows (the sodium-unit pattern).
    @AppStorage(SharedStore.mealIconKey, store: SharedStore.defaults) private var mealIconRaw = "plate"

    private var nameLine: some View {
        HStack(spacing: 4) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            Text(name)
                .foregroundStyle(.primary)
            // Marks read at .callout — .caption2 made them squint-sized
            // beside the body-size name (the user, 2026-07-23).
            if aiGenerated {
                Text(verbatim: "✨")
                    .font(.callout)
                    .accessibilityLabel("AI estimated")
            }
            if isMeal {
                // The meal mark (Appearance-configurable emoji),
                // replacing the old "Meal" text capsule — one mark
                // grammar beside the name.
                Text(verbatim: SharedStore.mealEmoji(for: mealIconRaw))
                    .font(.callout)
                    .accessibilityLabel("Meal")
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
                Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal · \(metric.captionText(metricAmount, sodium: sodiumUnit))")
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
                Text(metric.captionText(metricAmount, sodium: sodiumUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
