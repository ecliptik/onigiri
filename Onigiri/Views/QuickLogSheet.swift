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
    @Environment(\.modelContext) private var context
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @State private var isLoggingWater = false
    @Query(sort: \Meal.name) private var meals: [Meal]
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var kind: QuickActions.QuickLogKind = .foods
    @State private var kindLoaded = false
    @State private var searchText = ""
    /// Drives the whole search-active state (not just keyboard focus):
    /// an active search hides the toolbar, so sub-sheets must be able
    /// to deactivate it entirely or Done never comes back.
    @State private var searchPresented = false
    @State private var isLogging = false
    @State private var onlineSearch = OnlineFoodSearch()
    @State private var isLookingUpBarcode = false
    /// One sheet slot, like TodayView's: chained .sheet modifiers on one
    /// view compete, and the known-barcode scan path set the portion
    /// sheet while the scanner was still dismissing — it could silently
    /// fail to present, eating the scan.
    @State private var activeSheet: ActiveSheet?
    @State private var showLibraryImporter = false

    private enum ActiveSheet: Identifiable {
        case portion(PortionTarget)
        case scanner
        case form(ProductPrefill)
        case editFood(Food)
        case editMeal(Meal)

        var id: String {
            switch self {
            case .portion(let target): "portion-\(target.name)"
            case .scanner: "scanner"
            case .form(let prefill): "form-\(prefill.id)"
            case .editFood(let food): "editFood-\(food.persistentModelID.hashValue)"
            case .editMeal(let meal): "editMeal-\(meal.uuid.uuidString)"
            }
        }
    }
    /// Last week's distinct logged foods, newest first (HealthKit history).
    @State private var recents: [FoodLogEntry] = []
    /// History rows built from `recents` — cached because building them
    /// scans the food library per entry and formats a relative date per
    /// row, which used to rerun on every search keystroke. Rebuilt when
    /// the recents load and when any library name changes.
    @State private var historyRows: [Item] = []

    /// The rebuild trigger for `historyRows`: its twin-exclusion depends
    /// exactly on the set of library names.
    private var libraryNames: [String] {
        meals.map(\.name) + foods.map(\.name)
    }

    private struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        let isFavorite: Bool
        let category: String?
        var recency: Date = .distantPast
        var food: Food?
        var meal: Meal?
        /// True for HealthKit-history rows with no library twin — they
        /// re-log their own values ("as last logged").
        var isHistory = false
        var isMeal: Bool { meal != nil }
    }

    /// The library half of the list, CACHED like historyRows: building
    /// it walks every meal's relationships and copies every food's
    /// nutrient dictionary, and a computed property re-ran all of it on
    /// each search keystroke (the app's most-typed surface). Rebuilt on
    /// open, when library names change, when a sub-sheet closes (edits,
    /// portion picks), and after a log (recency bumps reorder it).
    @State private var libraryItems: [Item] = []

    private func buildLibraryItems() -> [Item] {
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
                recency: meal.recencyDate,
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
                recency: food.recencyDate,
                food: food
            )
        }
        return mealItems + foodItems
    }

    /// History-only rows: last week's logged foods with no library twin
    /// (library rows carry their own recency already, and meal-named
    /// entries would duplicate the meal rows).
    private func historyItems() -> [Item] {
        recents.compactMap { entry in
            guard !isMealName(entry.name),
                  !foods.contains(where: {
                      $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame
                  })
            else { return nil }
            return Item(
                id: "recent-\(entry.id.uuidString)",
                name: entry.name,
                detail: entry.date.formatted(.relative(presentation: .named)),
                kcal: entry.kcal,
                sodiumMg: entry.sodiumMg,
                nutrients: entry.nutrients,
                isFavorite: false,
                category: entry.category.rawValue,
                recency: entry.date,
                isHistory: true
            )
        }
    }

    /// The scope's pool, ranked purely by recency (Micheal: no favorite
    /// boost — "what I actually eat" order), name for stability.
    private func pool(_ items: [Item]) -> [Item] {
        let scoped = items.filter { item in
            switch kind {
            case .meals: item.isMeal
            case .favorites: item.isFavorite
            case .foods, .all, .scan: !item.isMeal
            }
        }
        let matched = searchText.isEmpty ? scoped : scoped.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText)
                || (item.category?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return matched.sorted { lhs, rhs in
            if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// A history entry is "a meal" when its name still matches the meal
    /// library — those rows would duplicate the meal rows.
    private func isMealName(_ name: String) -> Bool {
        meals.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        let items = libraryItems + historyRows
        let ranked = pool(items)
        NavigationStack {
            List {
                // The scan entry, a labeled row like Foods' (the user:
                // the toolbar icon was the odd one out once Foods grew
                // its row — same affordance, same place, both screens).
                // Hidden while searching so results lead.
                if searchText.isEmpty {
                    Section {
                        Button {
                            activeSheet = .scanner
                        } label: {
                            ScanBarcodeLabel()
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
                // Water leads the sheet, above Recent in every scope
                // (Micheal moved it off Today's header — one + button,
                // one place to log; widget/watch/app icon keep the
                // 1-tap paths). Tap logs the default serving into the
                // browsed day; long-press offers the other amounts.
                if searchText.isEmpty {
                    Section {
                        // Shaped like every other row: name, trailing
                        // serving (its "calories" column), the + to log.
                        // Plain primary text — the old full-row Button
                        // tinted it rice-toast; the blue drop is enough
                        // distinctness (the user).
                        HStack(spacing: 10) {
                            // The other-amounts hold lives on the label
                            // area only, so it can't swallow the +'s
                            // gestures (the Foods-row lesson).
                            HStack(spacing: 10) {
                                WaterIconView(raw: waterIcon)
                                Text("Water")
                                Spacer()
                                Text("\(SharedStore.waterServingOz, format: .number.precision(.fractionLength(0))) oz")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(.rect)
                            .contextMenu {
                                ForEach([8.0, 12, 16, 20, 24, 32], id: \.self) { oz in
                                    Button("\(oz, format: .number.precision(.fractionLength(0))) oz") {
                                        logWater(oz: oz)
                                    }
                                }
                            }
                            // The label area speaks for itself; the row
                            // must NOT take one big accessibilityLabel —
                            // that collapses it to a single element and
                            // hides the + from VoiceOver (and XCUITest;
                            // caught by the flow test on the 18.6 sim).
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Water, \(SharedStore.waterServingOz.formatted(.number.precision(.fractionLength(0)))) ounces per serving")
                            .accessibilityHint("Hold for other amounts")
                            LogButton(name: "Water", longPressName: "Log a serving") {
                                logWater(oz: SharedStore.waterServingOz)
                            } onLongPress: {
                                // Water's default portion IS the serving —
                                // a hold must not dead-end (and food rows
                                // taught thumbs that holding + logs).
                                logWater(oz: SharedStore.waterServingOz)
                            }
                            .disabled(isLoggingWater)
                        }
                    }
                }
                if !searchText.isEmpty || kind == .favorites {
                    // Search results (and the Favorites scope) read as
                    // one flat ranked list — no Recent split.
                    Section {
                        ForEach(ranked) { item in
                            row(item)
                        }
                        emptyState(pool: ranked, items: items)
                    }
                } else {
                    // The 10 most recently logged/used lead; the rest of
                    // the scope follows.
                    Section("Recent") {
                        ForEach(ranked.prefix(10)) { item in
                            row(item)
                        }
                        emptyState(pool: ranked, items: items)
                    }
                    if ranked.count > 10 {
                        Section("Everything else") {
                            ForEach(ranked.dropFirst(10)) { item in
                                row(item)
                            }
                        }
                    }
                }

                // Saved items rank first; the online database follows so a
                // one-off food can be logged without saving it.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    OnlineResultsSection(query: searchText, search: onlineSearch, onPick: { product in
                        route(product)
                    }, onAddManually: { name in
                        activeSheet = .form(ProductPrefill(product: ScannedProduct(
                            barcode: "", name: name, kcal: nil, sodiumMg: nil,
                            servingDescription: "", nutrients: NutrientValues()
                        )))
                    })
                }
            }
            .compactSections()
            .riceCanvas()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            // Music-style: the kind pills pinned on top of the results,
            // not scrolled away with them. Favorites replaced "All"; the
            // mixed view earned its keep only as a favorites shelf.
            .scopeBar(
                options: [
                    // Favorites leads (the user), matching Foods.
                    ("Favorites", QuickActions.QuickLogKind.favorites),
                    ("Foods", .foods),
                    ("Meals", .meals),
                ],
                selection: $kind
            )
            // The STANDARD system search field (Micheal: as close to
            // Apple's as possible) — the barcode scanner therefore lives
            // in the top toolbar, since the system field can't host an
            // accessory button.
            .searchable(
                text: $searchText,
                isPresented: $searchPresented,
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
                // "Done", not "Cancel": logging commits immediately (with
                // its own Undo), so dismissal cancels nothing — and the
                // sheet stays open for multi-item lunches. Confirm SLOT
                // (top trailing, emphasized) like Settings' Done — it sat
                // in the cancel slot, the app's one leading Done.
                // (The scanner moved from the toolbar into the list's
                // Scan Barcode row, matching Foods.)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if !kindLoaded {
                    kindLoaded = true
                    // Routing kinds aren't scopes: .scan lands on Foods
                    // with the scanner up, .all just lands on Foods. No
                    // auto-focused search — the keyboard-on-open version
                    // was too jarring (Micheal).
                    switch initialKind {
                    case .scan:
                        kind = .foods
                        activeSheet = .scanner
                    case .all:
                        kind = .foods
                    default:
                        kind = initialKind
                    }
                }
                libraryItems = buildLibraryItems()
                recents = (try? await HealthKitService().recentFoodEntries()) ?? []
                historyRows = historyItems()
            }
            // Library NAMES changed (add, remove, or in-place rename —
            // identity-based model-array comparison misses renames): the
            // twin-exclusion in the history rows must re-judge.
            .onChange(of: libraryNames) {
                libraryItems = buildLibraryItems()
                historyRows = historyItems()
            }
            // An active search hides the toolbar (no Done); deactivate
            // it when any sub-sheet opens so the sheet comes back to
            // its resting state after logging.
            .onChange(of: activeSheet?.id) { _, id in
                if id != nil {
                    searchPresented = false
                } else {
                    // A form or portion sheet just closed — values or
                    // recency may have moved; refresh the cache.
                    libraryItems = buildLibraryItems()
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .portion(let target):
                    PortionSheet(target: target) { quantity, category, _ in
                        log(
                            Item(id: target.name, name: target.name, detail: target.serving,
                                 kcal: target.kcal, sodiumMg: target.sodiumMg,
                                 nutrients: target.nutrients, isFavorite: false, category: nil),
                            quantity: quantity,
                            category: category
                        )
                    }
                    .presentationDetents([.medium, .large])
                case .scanner:
                    BarcodeScannerSheet { code in
                        lookUpBarcode(code)
                    }
                case .form(let prefill):
                    // New foods go through the full form — reviewable, complete,
                    // and saved to the library. Its Log action returns here
                    // (the sheet stays open for the next item).
                    FoodFormView(food: nil, prefill: prefill.product, logDate: logDate)
                case .editFood(let food):
                    FoodFormView(food: food)
                case .editMeal(let meal):
                    MealFormView(meal: meal)
                }
            }
            .fileImporter(isPresented: $showLibraryImporter, allowedContentTypes: [.json]) { result in
                ToastCenter.shared.show(LibraryTransfer.handlePickedFile(result, context: context))
            }
        }
        .toastHost()
    }

    /// Scope-aware empty states, rendered inside the leading section.
    @ViewBuilder
    private func emptyState(pool: [Item], items: [Item]) -> some View {
        if pool.isEmpty {
            if items.isEmpty {
                // Accurate copy: this sheet can create foods itself via
                // the scan button and online search.
                ContentUnavailableView {
                    Label("No saved foods yet", systemImage: "fork.knife")
                } description: {
                    Text("Scan a barcode or search online — logged foods are saved to your library.\n\nOr bring your library from another device: export it there (Settings → Export Library) and import the file here.")
                } actions: {
                    // Text-only: with a systemImage, iOS 26 collapses
                    // the label to a bare icon here.
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
                // Compact on purpose, NOT ContentUnavailableView: its
                // full-height layout shoved the Online section's search
                // button down under the bottom search bar.
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
            } else if kind == .favorites {
                Text("No favorites yet — swipe right on a food or meal to star it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if kind == .meals {
                Text("No saved meals yet — build one on the Library tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No saved foods yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            activeSheet = .portion(target)
        } else {
            activeSheet = .form(ProductPrefill(product: product))
        }
    }

    /// Scan → library check → fetch the product if it's new. The single
    /// sheet slot re-presents on the item change, so a known barcode can
    /// hand the dismissing scanner off to the portion sheet directly.
    private func lookUpBarcode(_ code: String) {
        if let target = libraryTarget(forBarcode: code) {
            activeSheet = .portion(target)
            return
        }
        isLookingUpBarcode = true
        Task {
            defer { isLookingUpBarcode = false }
            do {
                let product = try await OpenFoodFactsClient().product(barcode: code)
                activeSheet = .form(ProductPrefill(product: product))
            } catch {
                // Transient failures toast, like everything else; the
                // sheet has its own toastHost (the root's renders behind
                // presented sheets).
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    /// In a sheet named "Log", tap = log: the row opens the portion
    /// sheet (the + capsule keeps the fast paths — meals one-tap).
    /// Editing moved to a leading swipe; tap-to-edit in the middle of a
    /// logging flow was the one surprising row in the app.
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
            LogButton(
                name: item.name,
                longPressName: item.isMeal ? "Custom portion" : "Log default portion"
            ) {
                if item.isMeal {
                    log(item, quantity: 1, category: PortionTarget.category(from: item.category))
                } else {
                    // The portion sheet's log path loses the model ref —
                    // bump recency at pick time.
                    item.food?.lastUsedAt = .now
                    activeSheet = .portion(makePortionTarget(for: item))
                }
            } onLongPress: {
                // Each type's long press is the other's tap: meals get
                // the portion sheet, foods skip it and log the default
                // portion (matching the Foods screen).
                item.food?.lastUsedAt = .now
                item.meal?.lastUsedAt = .now
                if item.isMeal {
                    activeSheet = .portion(makePortionTarget(for: item))
                } else {
                    log(item, quantity: 1, category: PortionTarget.category(from: item.category))
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            item.food?.lastUsedAt = .now
            item.meal?.lastUsedAt = .now
            activeSheet = .portion(makePortionTarget(for: item))
        }
        .swipeActions(edge: .leading) {
            // History rows have no library twin — nothing to edit.
            if !item.isHistory {
                Button {
                    if let meal = item.meal {
                        activeSheet = .editMeal(meal)
                    } else if let food = item.food {
                        activeSheet = .editFood(food)
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.riceToast)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit") {
            if let meal = item.meal {
                activeSheet = .editMeal(meal)
            } else if let food = item.food {
                activeSheet = .editFood(food)
            }
        }
    }

    private func makePortionTarget(for item: Item) -> PortionTarget {
        PortionTarget(
            name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
            // A history row's detail is its relative log date, not a
            // serving description.
            nutrients: item.nutrients, serving: item.isHistory ? "as last logged" : item.detail,
            defaultCategory: PortionTarget.category(from: item.category)
        )
    }

    /// Water into the browsed day (backfill included), staying open
    /// like every other log here.
    private func logWater(oz: Double) {
        guard !isLoggingWater else { return }
        isLoggingWater = true
        Task {
            defer { isLoggingWater = false }
            await LogActions.logWater(oz: oz, date: logDate)
        }
    }

    /// Logs and STAYS OPEN — the toast confirms, and an ad-hoc
    /// three-item lunch used to mean three full sheet round-trips.
    /// Done (toolbar) leaves.
    private func log(_ item: Item, quantity: Double, category: FoodCategory) {
        guard !isLogging else { return }
        // Recency drives the sort under favorites.
        item.food?.lastUsedAt = .now
        item.meal?.lastUsedAt = .now
        isLogging = true
        Task {
            _ = await LogActions.logFood(
                name: item.name,
                kcal: item.kcal * quantity,
                sodiumMg: item.sodiumMg * quantity,
                nutrients: item.nutrients.scaled(by: quantity),
                category: category,
                date: logDate
            )
            isLogging = false
            // Recency moved — refresh the cached list order and the
            // watch's "Recent foods".
            libraryItems = buildLibraryItems()
            PhoneSyncService.shared.push(from: context)
        }
    }
}

#Preview {
    QuickLogSheet()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
