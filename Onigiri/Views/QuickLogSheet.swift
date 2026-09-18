import SwiftUI
import SwiftData
import WidgetKit
import OnigiriKit

/// One-stop logging from the Today screen: favorites up top, one field
/// in the door bar below that searches the library, describes a plate
/// to AI and searches online at once; tap a row to log it. Long-press a
/// row for portions.
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
    @State private var kind: QuickActions.QuickLogKind = .favorites
    @State private var kindLoaded = false
    /// The third library surface with the shared sort (the user).
    /// Recent default preserves the sheet's Recent/Everything-else
    /// split; the other orders read as one flat list.
    @AppStorage("logSheetSort") private var sortRaw = LibrarySort.recent.rawValue
    // The secondary row metric follows the first tracked slot (the
    // user: sodium was hardcoded; now it customizes with Settings).
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var libraryMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }

    private var librarySort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }
    /// The sheet's ONE query: what's typed into the door bar's "Search,
    /// or Describe Food or Meal" field. It drives the library search
    /// (`searchGroups`), the AI estimate row and the online search all
    /// at once. There was a second field — the standard `.searchable`
    /// drawer, library-only — until 2026-09-17, when the user folded it
    /// into this one ("Unify the Search dialog on Log into the Describe
    /// Food or Meal … Remove the old Search at the top"). CLAUDE.md,
    /// "Food entry", has the rule and the history of the split.
    @State private var describeQuery = ""
    /// The describe field's focus. The leading toolbar button reads
    /// it: while the keyboard is up that button puts the keyboard
    /// away instead of closing the sheet (the user, 2026-09-17).
    @FocusState private var describeFocused: Bool
    /// Bumped by the composer's "Estimate with AI" — a consumable
    /// token, never a Bool (CLAUDE.md's dead-request-flag landmine).
    /// `AIEstimateSection` consumes it and clears it.
    @State private var estimateToken: UUID?
    /// Raised by the estimate while it runs, so the button can say
    /// "Estimating…" and refuse a second tap.
    @State private var isEstimating = false
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
        /// The notice rides the case so a re-presented scanner can say
        /// why it's back (a barcode the database didn't have).
        /// The door carries in the VALUE, never a flag beside it —
        /// a sheet reads its content closure when it presents, and a
        /// mode set in the same breath as a Bool can arrive late
        /// (`plans/PLAN-multi-item-import.md`, the same lesson the
        /// menu listing learned).
        case scanner(notice: String?, opening: ScanSheet.Opening?)
        /// The composer's "+": camera, photos or a file.
        case addContext
        case form(ProductPrefill)
        case editFood(Food)
        case editMeal(Meal)

        var id: String {
            switch self {
            case .portion(let target): "portion-\(target.name)"
            case .scanner(let notice, let opening):
                "scanner-\(notice ?? "")-\(opening.map(String.init(describing:)) ?? "")"
            case .addContext: "addContext"
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

    private struct Item: Identifiable, LibrarySearchable {
        let id: String
        let name: String
        let detail: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        let isFavorite: Bool
        let category: String?
        /// AI-estimate provenance — ✨ in the row, metadata on the log.
        var aiGenerated = false
        var recency: Date = .distantPast
        var food: Food?
        var meal: Meal?
        /// True for HealthKit-history rows with no library twin — they
        /// re-log their own values ("as last logged").
        var isHistory = false
        /// Portions the item's values already represent (a history row
        /// mirroring a 3-portion entry re-logs as 3, so a later edit
        /// still knows the per-portion basis). 1 for library items.
        var baseQuantity: Double = 1
        /// Meal composition (per-portion) — from the library meal, or
        /// carried through a history row so re-logs keep the breakdown.
        var mealItems: [LoggedMealItem] = []
        var isMeal: Bool { meal != nil }

        // How the cross-scope search sees a row (LibrarySearchable).
        // Spelled out rather than renaming the stored properties: the
        // protocol's names are deliberately distinct so a witness can't
        // be satisfied by accident.
        var searchName: String { name }
        var searchCategory: String? { category }
        var isStarred: Bool { isFavorite }
        var isMealRow: Bool { isMeal }
        var isHistoryRow: Bool { isHistory }
        var searchRecency: Date { recency }
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
                aiGenerated: meal.aiGenerated,
                recency: meal.recencyDate,
                meal: meal,
                mealItems: meal.loggedItems
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
                aiGenerated: food.aiGenerated,
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
                aiGenerated: entry.aiGenerated,
                recency: entry.date,
                isHistory: true,
                baseQuantity: entry.quantity,
                mealItems: entry.mealItems
            )
        }
    }

    /// The BROWSING pool: the selected scope, ranked purely by recency
    /// (the user: no favorite boost — "what I actually eat" order), name
    /// for stability.
    ///
    /// Search does NOT come through here. It used to, and the scope
    /// filter ran FIRST — so searching "nectarine" on the Meals scope
    /// returned nothing while the nectarine sat in the library (the
    /// user, 2026-08-07). A query crosses every scope and groups
    /// instead; see `searchGroups`.
    private func pool(_ items: [Item]) -> [Item] {
        let scoped = items.filter { item in
            switch kind {
            case .meals: item.isMeal
            case .favorites: item.isFavorite
            case .foods, .all, .scan: !item.isMeal
            }
        }
        return scoped.sorted { lhs, rhs in
            LibrarySearch.isOrderedBefore(
                (lhs.recency, lhs.name), (rhs.recency, rhs.name),
                byRecency: librarySort == .recent
            )
        }
    }

    /// A query searches the WHOLE library — Favorites, Foods, Meals,
    /// and the history rows — grouped, one home per row. The scope bar
    /// is a browsing control, not a search filter.
    private func searchGroups(_ items: [Item]) -> [(group: LibrarySearchGroup, items: [Item])] {
        LibrarySearch.groups(items, query: describeQuery, sortByRecency: librarySort != .name)
    }

    /// A history entry is "a meal" when its name still matches the meal
    /// library — those rows would duplicate the meal rows.
    private func isMealName(_ name: String) -> Bool {
        meals.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        let items = libraryItems + historyRows
        // ONE search-active predicate for the whole sheet: the water
        // row, the scope bar, and which list shape renders all have to
        // agree, or a whitespace-only query shows half of each state.
        let searching = !describeQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let ranked = searching ? [] : pool(items)
        let groups = searching ? searchGroups(items) : []
        // The online section offers its own Add Food once a search has
        // come back empty for the CURRENT words; the local dead-end
        // state below steps aside then, so a query with nothing behind
        // it anywhere shows one Add Food, not two.
        let onlineOffersAddFood = SharedStore.onlineLookups
            && !onlineSearch.isSearching
            && onlineSearch.results.isEmpty
            && describeQuery.trimmingCharacters(in: .whitespaces) == onlineSearch.lastQuery
        NavigationStack {
            List {
                // The scope picker rides IN the list, matching Foods
                // exactly. It was pinned above the list ("Music-style")
                // until 2026-09-16, when this sheet briefly carried a
                // native `.large` title: that grows on pull-down
                // overscroll while a pinned `safeAreaInset` (measured
                // against the LIST, not the nav bar) does not, and the
                // two visibly slid apart mid-gesture (the user, screen
                // recording). The title is inline now and never grows,
                // so pinning would work again; it stays a row
                // because Foods' is one and the two screens should
                // scroll the same way. Hidden while searching, same as
                // Foods: a query crosses every scope, so no segment can
                // be the true one.
                if !searching {
                    Section {
                        ScopeBar(
                            options: [
                                // Favorites leads (the user), matching Foods.
                                ("Favorites", QuickActions.QuickLogKind.favorites),
                                ("Foods", .foods),
                                ("Meals", .meals),
                            ],
                            selection: $kind
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                // A query's results: AI row → library → online, the
                // order decided for a unified field on 2026-07-19
                // (`plans/PLAN-unified-search.md`: saved staples one
                // glance away, online the new-food fallback). The AI
                // and online rows are exactly what the describe field
                // showed before the library search joined it; each is
                // tap-to-run, never per-keystroke, so typing costs
                // nothing but the local filter. The AI row leads
                // because the field's first name is Describe: a plate
                // no library has is what it's for.
                if searching {
                    // An estimate opens the FULL food form, editable
                    // down to every value — the same route unknown
                    // barcodes and labels take from here (the portion
                    // shortcut made estimates the odd one out;
                    // superseded 2026-07-20, the user). Its Log action
                    // writes to the browsed day and returns here.
                    if FoodIntelligence.isAvailable {
                        AIEstimateSection(
                            query: describeQuery,
                            startToken: $estimateToken,
                            isEstimating: $isEstimating
                        ) { product in
                            describeQuery = ""
                            activeSheet = .form(ProductPrefill(
                                product: product,
                                provenance: product.aiEngine?.estimateCaption))
                        }
                    }
                }
                // Water leads the library in every scope (Micheal moved
                // it off Today's header — one + button, one place to
                // log; widget/watch/app icon keep the 1-tap paths). Tap
                // logs the default serving into the browsed day;
                // long-press offers the other amounts. It is not a
                // library row, so a query can't find it through
                // `searchGroups`: it stays only while the query names
                // it (the user, 2026-09-17) — `LibrarySearch.namesWater`
                // is the rule, with its tests.
                if !searching || LibrarySearch.namesWater(describeQuery) {
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
                                Text(SharedStore.waterUnit.text(fromOz: SharedStore.waterServingOz))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(.rect)
                            .contextMenu {
                                // Round presets PER UNIT (237 mL buttons
                                // would be noise); logs store the exact
                                // converted oz either way.
                                if SharedStore.waterUnit == .fluidOunces {
                                    ForEach([8.0, 12, 16, 20, 24, 32], id: \.self) { oz in
                                        Button("\(oz, format: .number.precision(.fractionLength(0))) oz") {
                                            logWater(oz: oz)
                                        }
                                    }
                                } else {
                                    ForEach([200.0, 250, 330, 500, 750, 1_000], id: \.self) { ml in
                                        Button("\(ml, format: .number.precision(.fractionLength(0))) mL") {
                                            logWater(oz: WaterUnit.milliliters.toOz(ml))
                                        }
                                    }
                                }
                            }
                            // The label area speaks for itself; the row
                            // must NOT take one big accessibilityLabel —
                            // that collapses it to a single element and
                            // hides the + from VoiceOver (and XCUITest;
                            // caught by the flow test on the 18.6 sim).
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Water, \(SharedStore.waterUnit.value(fromOz: SharedStore.waterServingOz)) \(SharedStore.waterUnit.spoken(SharedStore.waterUnit.fromOz(SharedStore.waterServingOz))) per serving")
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
                if searching {
                    // Favorites → Foods → Meals → Recently Logged, one
                    // home per row (a starred food is under Favorites
                    // and NOT again under Foods), empty groups dropped.
                    ForEach(groups, id: \.group) { group in
                        Section(group.group.rawValue) {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        }
                    }
                    if groups.isEmpty {
                        Section {
                            emptyState(visible: 0, items: items, offerAddFood: !onlineOffersAddFood)
                        }
                    }
                    // Last: a one-off food logged without saving it, or
                    // a barcode-free product the library doesn't have
                    // yet — saved items ranked above.
                    if SharedStore.onlineLookups {
                        OnlineResultsSection(query: describeQuery, search: onlineSearch, onPick: { product in
                            describeQuery = ""
                            route(product)
                        }, onAddManually: { name in
                            describeQuery = ""
                            activeSheet = .form(ProductPrefill(product: ScannedProduct(
                                barcode: "", name: name, kcal: nil, sodiumMg: nil,
                                servingDescription: "", nutrients: NutrientValues()
                            )))
                        })
                    }
                } else if kind == .favorites || librarySort != .recent {
                    // The Favorites scope and the non-Recent sort orders
                    // read as one flat ranked list — no Recent split.
                    Section {
                        ForEach(ranked) { item in
                            row(item)
                        }
                        emptyState(visible: ranked.count, items: items)
                    }
                } else {
                    // The 10 most recently logged/used lead; the rest of
                    // the scope follows.
                    Section("Recent") {
                        ForEach(ranked.prefix(10)) { item in
                            row(item)
                        }
                        emptyState(visible: ranked.count, items: items)
                    }
                    if ranked.count > 10 {
                        Section("Everything else") {
                            ForEach(ranked.dropFirst(10)) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
            .compactSections()
            // Drag the results down and the keyboard goes with them —
            // the other half of the door bar's Done button, and what a
            // thumb already expects from Messages and Mail.
            // `.interactively` rather than `.immediately` because
            // scrolling a list of matches while still typing is the
            // normal thing to do here; only a deliberate downward drag
            // should take the keyboard.
            .scrollDismissesKeyboard(.interactively)
            // The scope bar's row asks for zero `listRowInsets` and is
            // refused: a minimum row height holds it at 52pt around a
            // 31pt segmented control, which CENTRES the control and
            // leaves ~10.5pt above and below it. Behind that row's
            // CLEAR background that isn't a card's padding, it is blank
            // canvas — 20.33pt above the Water card against 10pt below
            // (the user, 2026-09-17: "Above/below should match"). With
            // the floor gone the zero insets finally apply and the row
            // hugs its control, so every gap down the screen is the one
            // section spacing.
            //
            // Measured, because "row height" is exactly the kind of
            // thing that moves other rows by surprise: the scope row
            // 52 → 31, every food card still 74, the estimate row still
            // 52 (its own insets are untouched — it never asked for
            // zero). A row whose natural height is already past the
            // floor cannot notice this. Section-scoped was tried first
            // and the List ignored it; so was a negative `padding`,
            // which moved nothing.
            .environment(\.defaultMinListRowHeight, 0)
            .riceCanvas()
            .hardTopScrollEdge()
            // A STANDARD sheet header, like every other sheet in the app
            // (Settings, Add Food, Edit Meal…): "Log" inline and
            // centered, Cancel leading, Sort + Done trailing, the search
            // drawer directly beneath. This sheet spent one day
            // (2026-09-15 evening → 09-16) on the tabs' `.inlineLarge`
            // header with Cancel moved trailing — under that mode a
            // leading item in a sheet lands in the overflow menu — and
            // the collapsed state gave it away: with three trailing
            // controls the compact title can't center, so it sat at the
            // left edge with the buttons opposite, unlike any other
            // sheet (the user, 2026-09-16, from device: "Log heading in
            // the middle and Cancel button on the left side, like all
            // other menu screens"). The same preference was stated once
            // before (2026-07-19: this was the ONE sheet without a
            // leading Cancel). The large "Log" went with the mode; a
            // sheet with Cancel/Done is inline-titled in every Apple app
            // too. `.inlineLarge` is for the four TAB ROOTS only
            // (`inlineLargeTitle`, Style.swift). `flushTopContent` stays:
            // the List's extra top inset is NOT exclusive to that mode —
            // measured without it, this sheet's scope row sat ~63pt
            // under the search field against Foods' ~27pt. A native
            // title can't be reached by `recedesWithSheet()`, so it stays
            // crisp while a child sheet is up; the dimmed buttons plus
            // `recedesBehindSheet()`'s dim on the list still say
            // "something else is active" (accepted 2026-09-16, and it
            // stands).
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            // Flush while BROWSING — that's what keeps the scope row
            // level with Foods'. While SEARCHING the first row is the
            // AI estimate row instead, and flush against the nav bar
            // measured `gapAboveRow=0.0`: the row's top edge exactly on
            // the bar's bottom edge (the user, from device, twice —
            // "too close to the header", then "Still no padding" after
            // a Section wrap that only spaced it BELOW). A VALUE that
            // varies by state, never a modifier that appears and
            // disappears — the identity rule in CLAUDE.md's
            // SwiftData/SwiftUI landmines.
            //
            // ONE margin, both states, and it is the section gap — so
            // every gap down this screen is the same number: bar to
            // first row, row to row, card to card. It stopped varying
            // by state once the scope row lost its slack
            // (`defaultMinListRowHeight` above): that slack was what
            // used to push the scope bar 10.67pt down, and searching
            // had to match a figure browsing produced by accident.
            // Now both start at 142 because both are told to.
            //
            // Not 0: flush against the nav bar is where this started
            // (the user, twice — "too close to the header", "Still no
            // padding"). Not 16 either, which cleared the bar but
            // overshot the scope row's place and jumped on the first
            // keystroke.
            .flushTopContent(Layout.sectionSpacing)
            // NO `.searchable` drawer on this sheet — the ONE text field
            // is in the door bar below (the user, 2026-09-17: "Unify the
            // Search dialog on Log into the Describe Food or Meal …
            // Remove the old Search at the top of the Log dialog since
            // the feature now there"). Foods keeps its top drawer
            // (`librarySearch`, Style.swift): it is the library screen,
            // and it has no describe field to fold into. Two things the
            // drawer took with it, both good riddance: the system search
            // controller's "Close" that replaced Cancel/Sort/Done for
            // the rest of the sheet's life once the field was tapped
            // (measured 2026-09-15, `plans/PLAN-log-sheet-layout.md`),
            // and the transient onDisappear/onAppear a List section gets
            // under `.searchable` when the keyboard dismisses
            // (CLAUDE.md). A plain TextField does neither.
            //
            // The camera + describe doors, PINNED below the list and
            // above the home indicator (`entryDoorBar`, Style.swift, has
            // the twice-decided history). Never hidden now: the field
            // that IS the search lives in it, and hiding the bar while
            // searching would take the keyboard's field away.
            .entryDoorBar(isHidden: false) { composer }
            .toolbar {
                // Cancel leading, Sort + Done trailing — the shape every
                // other sheet in the app has (the user, 2026-07-19 and
                // again 2026-09-16). Logging commits immediately with its
                // own Undo, so both buttons just dismiss: Cancel is the
                // muscle-memory bail-out that can't accidentally log
                // anything; Done stays the affirmative finish for
                // multi-item lunches, in the confirm slot (emphasized)
                // like Settings' Done.
                // ALWAYS Cancel. It spent an hour on 2026-09-17 becoming
                // a keyboard-dismiss glyph while the field had focus —
                // the user's own suggestion, asked for as "Can we do
                // both?" — and the answer from the device was "I don't
                // like the keyboard icon in the upper [left]". The
                // keyboard's exit lives in the door bar's capsule now,
                // beside the text it dismisses. Leave this slot alone:
                // Cancel-left/Done-right is the shape settled three
                // times over (CLAUDE.md, "Food entry").
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // The in-flight online search dies with the
                        // sheet — clear() cancels its search/page tasks
                        // instead of letting them keep the model alive
                        // for one wasted round trip (audit, 2026-08-17;
                        // deliberately here, never .onDisappear —
                        // CLAUDE.md's .searchable teardown trap).
                        onlineSearch.clear()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .recedesWithSheet(activeSheet != nil)
                }
                // Sort is the item that may overflow first on iOS 27 —
                // Done (`.confirmationAction`) already resists it, and
                // the search drawer above means a narrow bar (large
                // Dynamic Type) has less room than it used to
                // (`plans/PLAN-log-sheet-layout.md`, 2026-09-15).
                // `.visibilityPriority` attaches to the ToolbarItem
                // itself, not the view inside it, so the branch has to
                // repeat the ToolbarItem — `sortMenu` keeps the Menu's
                // own body from being duplicated.
                if #available(iOS 27.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { sortMenu }
                        .visibilityPriority(.low)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { sortMenu }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onlineSearch.clear()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .keyboardShortcut(.return, modifiers: .command)
                    .recedesWithSheet(activeSheet != nil)
                }
            }
            .task {
                if !kindLoaded {
                    kindLoaded = true
                    // Routing kinds aren't scopes: both land on Favorites,
                    // .scan with the scanner already up. No auto-focused
                    // search — the keyboard-on-open version was too
                    // jarring (the user).
                    //
                    // Favorites here is deliberate and NOT the Foods tab's
                    // setting (Appearance → "Foods tab opens on", which the
                    // user moved to Foods on 2026-08-05). This is a
                    // LOGGING surface: what you reach for is usually
                    // something you've eaten before. Don't wire the two
                    // together without asking — they answer different
                    // questions.
                    switch initialKind {
                    case .scan:
                        kind = .favorites
                        activeSheet = .scanner(notice: nil, opening: nil)
                    case .all:
                        kind = .favorites
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
            .onChange(of: activeSheet?.id) { _, id in
                if id == nil {
                    // A form or portion sheet just closed — values or
                    // recency may have moved; refresh the cache.
                    libraryItems = buildLibraryItems()
                }
            }
            .recedesBehindSheet(activeSheet != nil)
            .fileImporter(isPresented: $showLibraryImporter, allowedContentTypes: [.json]) { result in
                ToastCenter.shared.show(LibraryTransfer.handlePickedFile(result, context: context))
            }
        }
        // On the NavigationStack, NOT the List — matching FoodsView's
        // own fix: presenting a sheet over a search drawer's view leaves
        // the drawer's search controller unable to take focus after the
        // dismissal, taps land but the keyboard never rises (iOS 26).
        // This sheet has no drawer since 2026-09-17, but the placement
        // costs nothing and stays where Foods' is.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .portion(let target):
                PortionSheet(target: target) { quantity, category, _ in
                    // Confirm only. The reconstructed Item below has
                    // no model refs, so `log`'s own bump can't reach
                    // the library row — this is what does.
                    markUsed(target.source)
                    log(
                        Item(id: target.name, name: target.name, detail: target.serving,
                             kcal: target.kcal, sodiumMg: target.sodiumMg,
                             nutrients: target.nutrients, isFavorite: false, category: nil,
                             aiGenerated: target.aiGenerated,
                             baseQuantity: target.baseQuantity,
                             mealItems: target.mealItems),
                        quantity: quantity,
                        category: category
                    )
                }
                .presentationDetents([.medium, .large])
            case .addContext:
                // The chooser raises its own pickers and hands back what
                // came OUT of them; the swap waits a turn, because
                // setting the slot synchronously inside a closure the
                // sheet follows with its own dismiss tears the NEW sheet
                // down with the old (CLAUDE.md, 2026-07-22).
                AddContextSheet(
                    onCamera: { Task { activeSheet = .scanner(notice: nil, opening: nil) } },
                    onPhoto: { item in
                        Task { activeSheet = .scanner(notice: nil, opening: .photo(item)) }
                    },
                    onFile: { url in
                        Task { activeSheet = .scanner(notice: nil, opening: .menuFile(url)) }
                    }
                )
                .presentationDetents([.height(260)])
            case .scanner(let notice, let opening):
                // A parsed label takes the unknown-barcode route: the
                // single sheet slot re-presents as the prefilled food
                // form, whose Log action returns here with logDate
                // intact. Deferred one turn — the sheet dismisses
                // itself right after this closure, and a synchronous
                // swap gets torn down by that dismissal.
                // `.logging` + `logDate`: a menu or multi-food read
                // here is ordered from — pick, confirm, log, back to
                // the list — and it writes into the day this sheet is
                // browsing, not today
                // (`plans/PLAN-multi-item-import.md`).
                ScanSheet(onCode: { code in
                    lookUpBarcode(code)
                }, onLabel: { parsed in
                    let prefill = ProductPrefill(product: parsed.scannedProduct())
                    Task { activeSheet = .form(prefill) }
                }, onFood: { product in
                    // An identified food photo takes the same route:
                    // the prefilled form, whose Log action returns
                    // here with logDate intact.
                    let prefill = ProductPrefill(product: product)
                    Task { activeSheet = .form(prefill) }
                }, purpose: .logging, logDate: logDate, notice: notice, opening: opening)
            case .form(let prefill):
                // New foods go through the full form — reviewable and
                // complete. Its Log action returns here (the sheet stays
                // open for the next item). AI-estimate prefills carry
                // their provenance caption in. `.logging`: you came here
                // to log, so the form offers Log / Log & Save — saving to
                // the library is the option, not the price of admission.
                FoodFormView(
                    food: nil, prefill: prefill.product,
                    prefillMessage: prefill.provenance, logDate: logDate,
                    purpose: .logging)
            case .editFood(let food):
                FoodFormView(food: food)
            case .editMeal(let meal):
                MealFormView(meal: meal)
            }
        }
        .toastHost()
    }

    /// What to do about a query the library doesn't answer, named as the
    /// controls that do it: "Add Food, Estimate with AI or Search Online"
    /// (the user, 2026-09-18). It replaces "Try different words, or tap
    /// Search Online." — a dead end is more useful pointing at the ways
    /// out than at the way back in.
    ///
    /// BUILT from what is on screen, never hardcoded. All three routes
    /// are gated — Add Food yields to the online section's own button
    /// for the same words, the estimate needs `isAvailable` and the
    /// search needs `onlineLookups` — and naming a control that isn't
    /// there is worse than saying less. The order matches the order the
    /// eye meets them: the button in this card, then the bar's two
    /// actions, left to right.
    private func deadEndHint(offerAddFood: Bool) -> String {
        var routes: [String] = []
        if offerAddFood { routes.append("Add Food") }
        if FoodIntelligence.isAvailable { routes.append("Estimate with AI") }
        if SharedStore.onlineLookups { routes.append("Search Online") }
        guard let last = routes.last else { return "Try different words." }
        guard routes.count > 1 else { return "\(last)." }
        return "\(routes.dropLast().joined(separator: ", ")) or \(last)."
    }

    /// Scope-aware empty states, rendered inside the leading section.
    /// `visible` is the count of rows actually rendered — the ranked
    /// pool when browsing, the flattened group total when searching.
    @ViewBuilder
    private func emptyState(visible: Int, items: [Item], offerAddFood: Bool = true) -> some View {
        if visible == 0 {
            if items.isEmpty {
                // Accurate copy: this sheet can create foods itself via
                // the scan button and online search.
                ContentUnavailableView {
                    Label("No saved foods yet", systemImage: "fork.knife")
                } description: {
                    Text("Scan a barcode or search online — logged foods are saved to your Food Library.")
                } actions: {
                    // Text-only: with a systemImage, iOS 26 collapses
                    // the label to a bare icon here.
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
            } else if !describeQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                // Compact on purpose, NOT ContentUnavailableView: its
                // full-height layout shoved the Add Food button down
                // under the door bar.
                //
                // "In your library": the online row sits right under
                // this since the two searches share one field
                // (2026-09-17), so the copy says which one came up
                // empty. `offerAddFood` is false while that row is
                // offering its own Add Food for the same words — one
                // button for one dead end.
                VStack(spacing: 4) {
                    Text("No matches in your library")
                        .font(.headline)
                    // Names the BUTTONS, not a section: since 2026-09-17
                    // the online search is a composer action, and
                    // "search online below" pointed at a list section
                    // that no longer exists.
                    Text(deadEndHint(offerAddFood: offerAddFood))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                if offerAddFood {
                    Button {
                        activeSheet = .form(ProductPrefill(product: ScannedProduct(
                            barcode: "",
                            name: describeQuery.trimmingCharacters(in: .whitespaces),
                            kcal: nil, sodiumMg: nil,
                            servingDescription: "", nutrients: NutrientValues()
                        )))
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                }
            } else if kind == .favorites {
                Text("No favorites yet — swipe right on a food or meal to star it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if kind == .meals {
                Text("No saved meals yet — build one in your Food Library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No saved foods yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The composer: the text row and the actions on that text. Split
    /// out of the body because the argument list grew past what the
    /// type checker will do inside a `List` — "unable to type-check
    /// this expression in reasonable time", which is a size complaint,
    /// not a correctness one.
    private var composer: some View {
        EntryDoorBar(
            scanBusy: isLookingUpBarcode,
            describeQuery: $describeQuery,
            onScan: { activeSheet = .scanner(notice: nil, opening: nil) },
            // Both land in the scan sheet's ONE cascade — a photo reads
            // the way a photographed label does, a PDF the way a shared
            // menu does.
            onDescribeSubmit: { Task { await onlineSearch.search(describeQuery) } },
            describeFocused: $describeFocused,
            // "Describe" only while something can be described TO — with
            // AI and online lookups both off the field is library search
            // alone, and the prompt promises just that (the camera
            // door's own rule: a label only promises what it can keep).
            describePrompt: FoodIntelligence.isAvailable || SharedStore.onlineLookups
                ? "Search or Describe Food"
                : "Search Foods and Meals",
            onAddContext: { activeSheet = .addContext },
            // The actions, gated on the same two switches the list
            // sections were: nothing offers a door that isn't there.
            onEstimate: FoodIntelligence.isAvailable ? { estimateToken = UUID() } : nil,
            onSearchOnline: SharedStore.onlineLookups
                ? { Task { await onlineSearch.search(describeQuery) } }
                : nil,
            isEstimating: isEstimating,
            searchesLibrary: true
        )
    }

    /// The Foods screen's sort circle, third surface — kept on the
    /// trailing edge to match Foods/Today/Calendar (and clear of the
    /// leading back-swipe zone).
    private var sortMenu: some View {
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
        .recedesWithSheet(activeSheet != nil)
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
        // Online lookups off = the scanner reads labels only; say why
        // the barcode did nothing instead of failing silently.
        guard SharedStore.onlineLookups else {
            ToastCenter.shared.show("Online lookups are off — enable in Settings to look up barcodes")
            return
        }
        BarcodeRouter.lookUp(
            code,
            savedTarget: { libraryTarget(forBarcode: $0) },
            setLookingUp: { isLookingUpBarcode = $0 },
            presentPortion: { activeSheet = .portion($0) },
            presentForm: { activeSheet = .form($0) },
            // Straight back to the camera, saying why — the panel is in
            // their hand and the scanner already reads labels.
            presentLabelScan: {
                activeSheet = .scanner(notice: BarcodeRouter.missNotice, opening: nil)
            }
        )
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
                metric: libraryMetric,
                metricAmount: libraryMetric.itemAmount(
                    sodiumMg: item.sodiumMg, nutrients: item.nutrients) ?? 0,
                isFavorite: item.isFavorite,
                isMeal: item.isMeal,
                aiGenerated: item.aiGenerated
            )
            LogButton(
                name: item.name,
                longPressName: item.isMeal ? "Custom portion" : "Log default portion"
            ) {
                if item.isMeal {
                    log(item, quantity: 1, category: PortionTarget.category(from: item.category))
                } else {
                    // No bump: the sheet's confirm handler stamps
                    // `PortionTarget.source` once something is logged.
                    activeSheet = .portion(makePortionTarget(for: item))
                }
            } onLongPress: {
                // Each type's long press is the other's tap: meals get
                // the portion sheet, foods skip it and log the default
                // portion (matching the Foods screen). `log` bumps
                // recency itself, so neither branch does it here.
                if item.isMeal {
                    activeSheet = .portion(makePortionTarget(for: item))
                } else {
                    log(item, quantity: 1, category: PortionTarget.category(from: item.category))
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            // Opening the portion sheet is how you LOOK at a row here,
            // and it used to reorder the list underneath you.
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

    /// Recency bump + explicit save: log taps are the app's most
    /// frequent SwiftData write, and autosave's crash window silently
    /// reverted Recent sort (2026-07-20 audit — the delete alerts got
    /// this discipline in v2.2.0, these sites never did).
    private func markUsed(_ item: Item) {
        item.food?.lastUsedAt = .now
        item.meal?.lastUsedAt = .now
        context.saveOrLog("recency")
    }

    /// The same bump, from a portion target that has come back through
    /// the sheet. Resolved against the loaded queries rather than
    /// `context.model(for:)` — see FoodsView's twin for why.
    private func markUsed(_ id: PersistentIdentifier?) {
        guard let id else { return }
        if let food = foods.first(where: { $0.persistentModelID == id }) {
            food.lastUsedAt = .now
        } else if let meal = meals.first(where: { $0.persistentModelID == id }) {
            meal.lastUsedAt = .now
        } else {
            return
        }
        context.saveOrLog("recency")
    }

    private func makePortionTarget(for item: Item) -> PortionTarget {
        PortionTarget(
            name: item.name, kcal: item.kcal, sodiumMg: item.sodiumMg,
            // A history row's detail is its relative log date, not a
            // serving description.
            nutrients: item.nutrients, serving: item.isHistory ? "as last logged" : item.detail,
            defaultCategory: PortionTarget.category(from: item.category),
            aiGenerated: item.aiGenerated,
            baseQuantity: item.baseQuantity,
            mealItems: item.mealItems,
            // nil for a history row: it has no library twin to bump.
            source: item.food?.persistentModelID ?? item.meal?.persistentModelID
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
        markUsed(item)
        isLogging = true
        Task {
            _ = await LogActions.logFood(
                name: item.name,
                kcal: item.kcal * quantity,
                sodiumMg: item.sodiumMg * quantity,
                nutrients: item.nutrients.scaled(by: quantity),
                category: category,
                date: logDate,
                aiGenerated: item.aiGenerated,
                quantity: quantity * item.baseQuantity,
                mealItems: item.mealItems
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
