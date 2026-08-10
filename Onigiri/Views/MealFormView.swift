import SwiftUI
import SwiftData
import OnigiriKit

/// Create or edit a one-tap meal by picking quantities of saved foods.
struct MealFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]

    var meal: Meal?

    @State private var name = ""
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    /// The order foods JOINED the meal, so a just-added one lands at the
    /// END of the member list — where the eye already is — instead of
    /// wherever recency or the alphabet drops it. Derived state: it must
    /// stay OUT of `FieldsSnapshot`, or a pure re-order would read as an
    /// unsaved change and raise the discard alert.
    @State private var addOrder: [PersistentIdentifier] = []
    @State private var category: String?
    @State private var isFavorite = false
    @State private var foodFilter = ""
    /// Recent-first by default (the user — the foods you just added are
    /// the ones the meal is for); remembered across builds. Shares the
    /// Foods screen's option set (Favorites / Recent / Name).
    @AppStorage("mealBuilderSort") private var sortRaw = LibrarySort.recent.rawValue

    private var librarySort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }
    // The Total's secondary metric follows the first tracked slot (the
    // user: sodium was hardcoded; now it customizes with Settings).
    // Do NOT "simplify" this to kcal-only: it was removed on 2026-08-09
    // as a stray sodium reading and RESTORED the same day once it was
    // clear the figure already follows Settings → Metrics — set slot 1
    // to Protein and this line reads "12 g protein". Every Foods/Log
    // library row and the portion sheet's "Will log" show the same pair.
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var libraryMetric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }
    /// Cancel/drag with edits confirms first — a half-built meal used
    /// to vanish on a stray swipe.
    @State private var confirmDiscard = false
    @State private var initialSnapshot: FieldsSnapshot?
    @State private var isSuggestingName = false
    /// Stored so dismissing the sheet cancels an in-flight suggestion
    /// (BYO-AI providers bill the request either way otherwise).
    @State private var suggestTask: Task<Void, Never>?
    /// Components from a described meal that the library does NOT already
    /// have, awaiting review. NOTHING is written to the library until
    /// Save — Cancel leaves it untouched — so each one holds the
    /// estimate's values until then. A component the library DOES have
    /// never lands here: `apply(_:)` turns it into an ordinary pick,
    /// which is what Save would have made of it anyway.
    @State private var pending: [PendingComponent] = []
    /// Which engine produced `pending` — an unreachable provider hands
    /// off to Apple Intelligence, and the footer below is the only
    /// place that says where these numbers came from.
    @State private var pendingEngine: AIProvider = .onDevice
    /// Raised by the estimate row while inference runs, so the ✨ name
    /// button goes quiet: two concurrent calls serialize on-device and
    /// double-bill a BYO-AI provider.
    @State private var isEstimatingMeal = false
    /// The AI's accepted name suggestion — the meal is marked ✨ only
    /// when the SAVED name is the suggestion, untouched.
    @State private var suggestedName: String?
    /// Provenance carried over when editing an already-AI-named meal.
    @State private var wasAINamed = false
    @State private var originalName = ""
    @FocusState private var quantityFocused: Bool

    /// One reviewed component of a described meal — always one the
    /// library lacks, so Save mints it (see `pending`).
    private struct PendingComponent: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let portion: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        var quantity: Double = 1
    }

    /// One row of "In this meal" — a library pick, or a component the
    /// estimate will mint. One type so a SINGLE ForEach spans both, which
    /// is what lets swipe-to-remove cover library picks (only the
    /// described components ever had it) and what keeps the two from
    /// looking like different kinds of thing.
    private struct MealMember: Identifiable {
        enum Kind {
            case library(Food)
            case pending(UUID)
        }
        let id: AnyHashable
        let kind: Kind
        let name: String
        let caption: String
        let quantity: Double
        let isEstimate: Bool
    }

    private struct FieldsSnapshot: Equatable {
        var name: String
        var quantities: [PersistentIdentifier: Double]
        var category: String?
        var isFavorite: Bool
        /// A described meal is real work in progress — without this, a
        /// stray swipe discarded it without asking.
        var pending: [PendingComponent]
    }

    private var currentSnapshot: FieldsSnapshot {
        FieldsSnapshot(
            // Zero quantities are "not in the meal" — same as absent.
            name: name, quantities: quantities.filter { $0.value > 0 },
            category: category, isFavorite: isFavorite,
            pending: pending.filter { $0.quantity > 0 }
        )
    }

    private var isDirty: Bool {
        initialSnapshot.map { $0 != currentSnapshot } ?? false
    }

    /// Everything IN the meal: library picks in the order they joined,
    /// then the components Save will mint.
    ///
    /// Deliberately NOT filtered by the search field and NOT re-ordered
    /// by the sort menu. The meal is not a search result — losing sight
    /// of it while hunting the next food is the whole complaint this
    /// section answers (the user, 2026-08-09), and it retires the old
    /// "totals still count every selected food, filtered out of view or
    /// not" contradiction.
    private var members: [MealMember] {
        let position = Dictionary(
            uniqueKeysWithValues: addOrder.enumerated().map { ($0.element, $0.offset) })
        let picked = foods
            .filter { (quantities[$0.persistentModelID] ?? 0) > 0 }
            .sorted { left, right in
                let a = position[left.persistentModelID] ?? Int.max
                let b = position[right.persistentModelID] ?? Int.max
                // Swift's sort isn't stable, so the Int.max ties (a food
                // with no recorded position) need their own tiebreak or
                // they shuffle between evaluations.
                if a != b { return a < b }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        let library = picked.map { food in
            let quantity = quantities[food.persistentModelID] ?? 0
            return MealMember(
                id: AnyHashable(food.persistentModelID),
                kind: .library(food),
                name: food.name,
                caption: MealMemberCaption.text(quantity: quantity, kcalEach: food.kcal),
                quantity: quantity,
                // ✨ means "Save will add this to your library" in this
                // section, which is what the footer counts. An
                // AI-estimated food that's ALREADY saved doesn't get one.
                isEstimate: false)
        }
        return library + pending.map { component in
            MealMember(
                id: AnyHashable(component.id),
                kind: .pending(component.id),
                name: component.name,
                caption: component.quantity > 0
                    ? MealMemberCaption.text(
                        quantity: component.quantity, kcalEach: component.kcal,
                        portion: component.portion)
                    // Zeroed but still listed: a minted component has no
                    // library to fall back to, so it stays put — out of
                    // the count and the total — until it's swiped away.
                    : component.portion,
                quantity: component.quantity,
                isEstimate: true)
        }
    }

    /// The pick-from list: strictly what is NOT in the meal yet, since
    /// the members have their own section above.
    private var visibleFoods: [Food] {
        let trimmed = foodFilter.trimmingCharacters(in: .whitespaces)
        var pool = foods.filter { (quantities[$0.persistentModelID] ?? 0) == 0 }
        if !trimmed.isEmpty {
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        // The @Query is name-sorted; the other orders re-sort here (ties
        // break alphabetically, which the stable base order provides).
        switch librarySort {
        case .recent:
            return pool.sorted { $0.recencyDate > $1.recencyDate }
        case .name:
            return pool
        }
    }

    private var totalKcal: Double {
        foods.reduce(0) { $0 + $1.kcal * (quantities[$1.persistentModelID] ?? 0) }
            + pending.reduce(0) { $0 + $1.kcal * $1.quantity }
    }
    private var totalMetricAmount: Double {
        foods.reduce(0) { sum, food in
            let quantity = quantities[food.persistentModelID] ?? 0
            guard quantity > 0 else { return sum }
            let amount = libraryMetric.itemAmount(sodiumMg: food.sodiumMg, nutrients: food.nutrients) ?? 0
            return sum + amount * quantity
        } + pending.reduce(0) { sum, component in
            guard component.quantity > 0 else { return sum }
            let amount = libraryMetric.itemAmount(
                sodiumMg: component.sodiumMg, nutrients: component.nutrients) ?? 0
            return sum + amount * component.quantity
        }
    }
    /// Anything in the meal at all — picked from the library OR waiting in
    /// the review section. Gates Save, the Total's emphasis, and the ✨
    /// name button; a described meal has nothing in `quantities`, so
    /// reading only that hid the ✨ exactly when it was most useful.
    private var hasItems: Bool {
        quantities.values.contains { $0 > 0 } || pending.contains { $0.quantity > 0 }
    }

    var body: some View {
        // Bound once per evaluation, like FoodsView: each access to the
        // computed property re-filters and re-sorts the whole library,
        // and the sections read them more than once.
        let visibleFoods = visibleFoods
        let members = members
        let trimmedFilter = foodFilter.trimmingCharacters(in: .whitespaces)
        NavigationStack {
            Form {
                HStack {
                    TextField("Meal name", text: $name)
                        // Placeholder rides as the VALUE and vanishes
                        // once text is typed — same fix as the food
                        // form's Name field.
                        .accessibilityLabel("Meal name")
                    // One tap, one on-device suggestion, freely edited or
                    // retried — only on Apple Intelligence devices, and
                    // only once there are foods to name.
                    if FoodIntelligence.isAvailable, hasItems {
                        Button {
                            suggestName()
                        } label: {
                            Group {
                                if isSuggestingName {
                                    ProgressView()
                                } else {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.riceToast)
                                }
                            }
                            // HIG 44 pt tap target via hit area only —
                            // the negative inset must not move layout.
                            .contentShape(Rectangle().inset(by: -14))
                        }
                        .buttonStyle(.borderless)
                        // Quiet while a meal estimate runs: it names the
                        // meal itself, and two concurrent inferences
                        // serialize on-device / double-bill BYO-AI.
                        .disabled(isSuggestingName || isEstimatingMeal)
                        .accessibilityLabel("Suggest meal name")
                    }
                }
                Picker("Category", selection: $category) {
                    Text("None").tag(String?.none)
                    ForEach(FoodCategory.allCases) { option in
                        Text(option.rawValue).tag(String?.some(option.rawValue))
                    }
                }
                Toggle("Favorite", isOn: $isFavorite)
                // The running size of the meal, visible while picking
                // foods below (the user — the old bottom Total sat off
                // screen exactly when it was needed). The member rows
                // below report their own contribution, so this reads as
                // a sum of what's on screen. The trailing metric is the
                // customizable one — see `libraryMetric`.
                LabeledContent("Total") {
                    Text("\(totalKcal, format: .number.precision(.fractionLength(0))) kcal • \(libraryMetric.captionText(totalMetricAmount, sodium: SharedStore.sodiumUnit))")
                        .monospacedDigit()
                        .foregroundStyle(hasItems ? .primary : .secondary)
                }

                // The search field describes a MEAL as readily as it
                // filters foods (one field, the app-wide grammar): the
                // estimate row leads the food list whenever something is
                // typed, and a pick lands in the section below.
                if !trimmedFilter.isEmpty {
                    MealEstimateSection(
                        query: foodFilter,
                        isEstimating: $isEstimatingMeal
                    ) { meal in
                        apply(meal)
                    }
                }

                // The empty placeholder teaches the section on a new
                // meal, but not mid-search: there it would sit between
                // the estimate row and the results saying nothing.
                if !members.isEmpty || trimmedFilter.isEmpty {
                    membersSection(members)
                }

                Section {
                    ForEach(visibleFoods) { food in
                        MealComponentRow(
                            name: food.name,
                            caption: "\(food.kcal.formatted(.number.precision(.fractionLength(0)))) kcal",
                            stepQuantity: binding(for: food),
                            typedQuantity: typedBinding(for: food),
                            quantityFocused: $quantityFocused)
                    }
                    if visibleFoods.isEmpty {
                        Text(emptyLibraryMessage(filter: trimmedFilter))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        // Not "Foods": the section above it is foods too,
                        // and this one is the pantry you draw from.
                        Text("Add from your library")
                        Spacer()
                        // Recent leads; the menu swaps order (remembered).
                        Menu {
                            Picker("Sort", selection: $sortRaw) {
                                ForEach(LibrarySort.allCases, id: \.rawValue) { option in
                                    Text(option.label).tag(option.rawValue)
                                }
                            }
                        } label: {
                            Label(librarySort.label,
                                  systemImage: "arrow.up.arrow.down")
                                .font(.footnote)
                        }
                        .textCase(nil)
                        .accessibilityLabel("Sort foods")
                    }
                }
            }
            .compactSections()
            .riceCanvas()
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            // System search, matching Foods and the Log sheet (bottom
            // placement on iOS 26). The prompt names both jobs: the same
            // field filters the library and describes a meal — the
            // one-field decision from PLAN-unified-search, not a second
            // door (2026-07-29).
            .searchable(text: $foodFilter, prompt: "Search foods or describe a meal")
            .onDisappear { suggestTask?.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasItems)
                }
                // Decimal pads have no return key; surface a Done while a
                // quantity field is editing (the food form's pattern).
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
            // .immediately, not .interactively: after typing a portion
            // the pad stays up, and the very next gesture is a scroll to
            // find the NEXT food — the keyboard must not eat half the
            // list (the user).
            .scrollDismissesKeyboard(.immediately)
            // Scoped to the two things that move rows: a picked food
            // animates up into the member section instead of teleporting,
            // and a described meal's components arrive the same way.
            .animation(.default, value: quantities)
            .animation(.default, value: pending)
            // Select-all on focus so typing replaces a portion instead
            // of appending to it (the food form's pattern). The system
            // search field is exempt — selecting an in-progress query on
            // refocus would surprise.
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )) { note in
                guard let field = note.object as? UITextField,
                      !(field is UISearchTextField) else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(isDirty)
            .onAppear {
                if let meal {
                    name = meal.name
                    originalName = meal.name
                    wasAINamed = meal.aiGenerated
                    category = meal.category
                    isFavorite = meal.isFavorite
                    quantities = Dictionary(uniqueKeysWithValues: meal.items.compactMap { item in
                        item.food.map { ($0.persistentModelID, item.quantity) }
                    })
                    // Reopen in the order it was built, not the
                    // alphabet's (best effort — SwiftData doesn't
                    // promise relationship order; `members` falls back
                    // to a name sort for anything missing).
                    addOrder = meal.items.compactMap { item in
                        item.quantity > 0 ? item.food?.persistentModelID : nil
                    }
                }
                initialSnapshot = currentSnapshot
            }
        }
        // This form is a SHEET, and the root toast host sits behind it —
        // so a toast raised while it's up renders under the sheet and is
        // never seen. The save toast survived only because it's followed
        // by dismiss(); the ✨ name suggestion's failure toast fired with
        // the sheet still up and showed NOTHING, which is exactly the
        // dead-button silence that toast was added to prevent (found
        // 2026-07-30). FoodFormView and QuickLogSheet host their own for
        // the same reason.
        .toastHost()
    }

    /// What's in the meal — ONE section for library picks and described
    /// components alike, because "what is in this meal" should have one
    /// answer in one place. Membership is carried structurally (this
    /// section, above the library) so it survives Differentiate Without
    /// Color and VoiceOver; the row's ×-badge and contribution caption
    /// reinforce it.
    private func membersSection(_ members: [MealMember]) -> some View {
        Section {
            if members.isEmpty {
                Text("Add foods below to build this meal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members) { member in
                    row(for: member)
                }
                .onDelete { offsets in remove(members, at: offsets) }
            }
        } header: {
            HStack {
                Text("In this meal")
                Spacer()
                // Count only — the Total above already carries kcal, and
                // two kcal figures a thumb apart read as a disagreement.
                let counted = members.count { $0.quantity > 0 }
                if counted > 0 {
                    Text(counted == 1 ? "1 item" : "\(counted) items")
                        .textCase(nil)
                }
            }
        } footer: {
            // The estimate's provenance, once, wherever its components
            // ended up in the list.
            if !pending.isEmpty {
                let minted = pending.count { $0.quantity > 0 }
                Text(minted == 0
                     ? pendingEngine.estimateCaption
                     : "\(pendingEngine.estimateCaption) Saving adds \(minted == 1 ? "1 food" : "\(minted) foods") to your library.")
            }
        }
    }

    @ViewBuilder
    private func row(for member: MealMember) -> some View {
        switch member.kind {
        case .library(let food):
            MealComponentRow(
                name: member.name, caption: member.caption, isMember: true,
                stepQuantity: binding(for: food),
                typedQuantity: typedBinding(for: food),
                quantityFocused: $quantityFocused)
        case .pending(let id):
            MealComponentRow(
                name: member.name, caption: member.caption,
                isEstimate: member.isEstimate, isMember: true,
                stepQuantity: pendingBinding(id: id),
                typedQuantity: pendingTypedBinding(id: id),
                quantityFocused: $quantityFocused)
        }
    }

    /// Three ways the pick-from list can be empty, and they are not the
    /// same thing: no library at all, a meal that has claimed all of it,
    /// or a search that matched nothing.
    private func emptyLibraryMessage(filter: String) -> String {
        if !filter.isEmpty { return "No foods match “\(filter)”." }
        if foods.isEmpty { return "No saved foods yet — add foods to your Food Library first." }
        return "Everything in your library is already in this meal."
    }

    /// Swipe-to-remove, spanning both member kinds: a library pick drops
    /// back to the list below at zero, a minted component is gone — it
    /// has no library to return to.
    private func remove(_ members: [MealMember], at offsets: IndexSet) {
        for member in offsets.map({ members[$0] }) {
            switch member.kind {
            case .library(let food):
                setQuantity(0, for: food.persistentModelID)
            case .pending(let id):
                pending.removeAll { $0.id == id }
            }
        }
    }

    /// A described meal lands here: components the library already has
    /// become ordinary picks, the rest become review rows. Nothing is
    /// written yet — Save does that.
    private func apply(_ meal: FoodIntelligence.DescribedMeal) {
        pendingEngine = meal.engine
        // The estimate names the meal too; a name already typed WINS (the
        // suggestName rule — the user's words outrank the model's).
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestTask?.cancel()
            isSuggestingName = false
            name = meal.name
            suggestedName = meal.name
        }
        let names = foods.map(\.name)
        var minted: [PendingComponent] = []
        for component in meal.components {
            if let index = ComponentMatch.index(of: component.name, in: names) {
                let food = foods[index]
                // Already saved: it joins as a plain pick, which is what
                // Save would have made of it regardless. A quantity the
                // user already chose STAYS — same precedent as the name.
                if (quantities[food.persistentModelID] ?? 0) == 0 {
                    setQuantity(1, for: food.persistentModelID)
                }
                continue
            }
            minted.append(PendingComponent(
                name: component.name, portion: component.portion,
                kcal: component.kcal, sodiumMg: component.sodiumMg,
                nutrients: component.nutrients))
        }
        pending = minted
        // The estimate answered the query; leaving it in the field would
        // keep the row (and the filtered food list) up over the members.
        foodFilter = ""
    }

    /// Fills the name field with the model's suggestion — unless the
    /// user typed their own while inference ran (theirs wins), and
    /// never silently: a declined model gets a toast, not a dead
    /// button (2026-07-20 audit).
    private func suggestName() {
        let members = foods
            .filter { (quantities[$0.persistentModelID] ?? 0) > 0 }
            .map(\.name)
            // A described meal's parts are named too — without them the
            // suggestion would be built from an empty list.
            + pending.filter { $0.quantity > 0 }.map(\.name)
        guard !members.isEmpty, !isSuggestingName else { return }
        isSuggestingName = true
        let nameWhenAsked = name
        suggestTask = Task {
            defer { isSuggestingName = false }
            let suggestion = await FoodIntelligence.suggestMealName(for: members)
            guard !Task.isCancelled else { return }
            guard let suggestion else {
                ToastCenter.shared.show("Couldn't suggest a name — try again.")
                return
            }
            guard name == nameWhenAsked else { return }
            name = suggestion
            suggestedName = suggestion
        }
    }

    /// Turns the reviewed components into meal items — the ONLY place a
    /// described meal writes to the library, and only from Save.
    ///
    /// Two SwiftData disciplines, both load-bearing:
    /// - the food is inserted BEFORE it's linked (`MealItem(food:)` traps
    ///   on a never-inserted food);
    /// - matching is re-run against the CURRENT library, because it can
    ///   change while this sheet is open — a component that had no match
    ///   when it was described may have been saved from another screen
    ///   since, and minting a twin would be wrong.
    private func mealItemsFromPending() -> [MealItem] {
        let live = foods
        let names = live.map(\.name)
        var items: [MealItem] = []
        for component in pending where component.quantity > 0 {
            if let index = ComponentMatch.index(of: component.name, in: names) {
                items.append(MealItem(food: live[index], quantity: component.quantity))
                continue
            }
            let food = Food(
                name: component.name,
                kcal: component.kcal,
                sodiumMg: component.sodiumMg,
                servingDescription: component.portion,
                barcode: nil,
                nutrients: component.nutrients,
                isFavorite: false,
                category: nil,
                // Provenance: these numbers are estimates, and the ✨ on
                // the food's library row is how that stays visible.
                aiGenerated: true)
            context.insert(food)
            items.append(MealItem(food: food, quantity: component.quantity))
        }
        return items
    }

    /// The ONE place a library food's quantity changes, so `addOrder`
    /// can't fall out of step with `quantities` — a food that left the
    /// meal and came back would otherwise keep its old position.
    private func setQuantity(_ value: Double, for id: PersistentIdentifier) {
        let clamped = min(max(value, 0), 20)
        if clamped > 0 {
            if !addOrder.contains(id) { addOrder.append(id) }
        } else {
            addOrder.removeAll { $0 == id }
        }
        quantities[id] = clamped
    }

    private func binding(for food: Food) -> Binding<Double> {
        Binding(
            get: { quantities[food.persistentModelID] ?? 0 },
            set: { newValue in
                // The first + selects ONE serving (the default portion),
                // not a quarter of one; ± nudges by quarters from there.
                let old = quantities[food.persistentModelID] ?? 0
                setQuantity((old == 0 && newValue == 0.25) ? 1 : newValue,
                            for: food.persistentModelID)
            }
        )
    }

    /// The typed-quantity flavor: empty shows the "—" placeholder
    /// instead of a wall of zeros, and typed values clamp to the
    /// stepper's range (0 means "not in the meal", reached by clearing
    /// the field). SEPARATE from the stepper's binding on purpose — the
    /// first-+ rule above would turn a typed "0.25" into a whole serving.
    private func typedBinding(for food: Food) -> Binding<Double?> {
        Binding(
            get: {
                let quantity = quantities[food.persistentModelID] ?? 0
                return quantity > 0 ? quantity : nil
            },
            set: { newValue in
                setQuantity(newValue ?? 0, for: food.persistentModelID)
            }
        )
    }

    /// The same pair for a minted component, addressed by id rather than
    /// index: the array is rebuilt whenever a match folds into
    /// `quantities`, and a stale index would write to the wrong row.
    private func pendingBinding(id: UUID) -> Binding<Double> {
        Binding(
            get: { pending.first { $0.id == id }?.quantity ?? 0 },
            set: { newValue in
                guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
                let old = pending[index].quantity
                pending[index].quantity = min(max((old == 0 && newValue == 0.25) ? 1 : newValue, 0), 20)
            }
        )
    }

    private func pendingTypedBinding(id: UUID) -> Binding<Double?> {
        Binding(
            get: {
                let quantity = pending.first { $0.id == id }?.quantity ?? 0
                return quantity > 0 ? quantity : nil
            },
            set: { newValue in
                guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
                pending[index].quantity = min(max(newValue ?? 0, 0), 20)
            }
        )
    }

    private func save() {
        // Every log confirms loudly; a silent edit-save read as a dead
        // button.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.show("Saved \(name.trimmingCharacters(in: .whitespaces)) ✓")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // ✨ when the saved name IS an accepted AI suggestion, or an
        // already-AI-named meal keeps its name; a hand-rewritten name
        // clears the mark.
        let aiNamed = if let suggestedName { trimmed == suggestedName }
                      else { wasAINamed && trimmed == originalName }
        var items = foods.compactMap { food -> MealItem? in
            let quantity = quantities[food.persistentModelID] ?? 0
            return quantity > 0 ? MealItem(food: food, quantity: quantity) : nil
        }
        items += mealItemsFromPending()
        // ...OR any member food is itself an AI estimate (the user,
        // 2026-07-29). The mark answers for the meal's NUMBERS as well as
        // its name now, so hand-rewriting the name of a described meal no
        // longer clears it while every value in it is still an estimate —
        // provenance sticks, exactly as it does on a food. Two accepted
        // consequences: a hand-BUILT meal made of estimated foods carries
        // the mark too (its numbers are estimates regardless of who
        // assembled it), and rename-clears-the-mark now applies only to
        // meals whose foods were all entered by hand — the case that rule
        // was written for.
        let aiComposed = items.contains { $0.food?.aiGenerated == true }
        if let meal {
            meal.name = trimmed
            meal.category = category
            meal.isFavorite = isFavorite
            meal.aiGenerated = aiNamed || aiComposed
            // Unlink before deleting: deleting items the meal still
            // references is the dangling-reference crash class.
            let oldItems = meal.items
            meal.items = items
            oldItems.forEach(context.delete)
        } else {
            context.insert(Meal(name: trimmed, items: items, isFavorite: isFavorite, category: category, aiGenerated: aiNamed || aiComposed))
        }
        // Explicit save (GoalUpsert's discipline) — see FoodFormView.
        try? context.save()
        PhoneSyncService.shared.push(from: context)
        dismiss()
    }
}

/// One row of the meal builder — a member of the meal, or a library food
/// waiting to join it. ONE view for both lists so they can't drift apart
/// visually (the OnlineResultsSection discipline).
///
/// `isMember` selects the cues that say "this is in the meal": the
/// ×-badged quantity, a medium-weight name, and a caption that reports
/// what the row CONTRIBUTES rather than what one serving costs. Those
/// reinforce the section boundary; they never carry the distinction
/// alone, so nothing here depends on seeing color.
private struct MealComponentRow: View {
    let name: String
    let caption: String
    var isEstimate = false
    var isMember = false
    /// Stepper and typed field take SEPARATE bindings on purpose: the
    /// stepper's first + means one whole serving, while a typed "0.25"
    /// means a quarter — one binding would promote the typed quarter.
    @Binding var stepQuantity: Double
    @Binding var typedQuantity: Double?
    @FocusState.Binding var quantityFocused: Bool

    var body: some View {
        // Quarter-step ± plus a TYPED quantity, exactly like the portion
        // sheet — half a Soylent belongs in a meal (the user). The field
        // bypasses the Stepper's range, so the bindings clamp too.
        Stepper(value: $stepQuantity, in: 0...20, step: 0.25) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name)
                            .fontWeight(isMember ? .medium : .regular)
                            // Membership must not depend on VoiceOver
                            // having announced the section header.
                            .accessibilityLabel(isMember ? "\(name), in this meal" : name)
                        if isEstimate {
                            // Mark size per the 2026-07-23 ruling —
                            // .caption2 read squint-sized beside a
                            // body-size name.
                            Text(verbatim: "✨")
                                .font(.callout)
                                .accessibilityLabel("AI estimate")
                        }
                    }
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                quantityControl
            }
            .padding(.trailing, 8)
        }
    }

    private var quantityControl: some View {
        // A plain trailing-aligned number, exactly like the portion
        // sheet's `LabeledContent("Serving")` field. A "×2" badge was
        // tried and REJECTED (the user, 2026-08-09): this quantity is a
        // SERVING everywhere else in the app, and inventing a
        // multiplication notation for it here made one screen speak its
        // own dialect. Membership is carried by the section, the name's
        // weight, and the contribution caption — it never needed a glyph.
        TextField("—", value: $typedQuantity,
                  format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 56)
            .monospacedDigit()
            .focused($quantityFocused)
            .accessibilityLabel("Servings of \(name)")
    }
}
