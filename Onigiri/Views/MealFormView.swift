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
    /// Components from a described meal, awaiting review. NOTHING is
    /// written to the library until Save — Cancel leaves it untouched —
    /// so a matched component holds its library food by ID and a new one
    /// holds the estimate's values until then.
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

    /// One reviewed component of a described meal. A `matchID` means the
    /// library already has this food and Save links to it (its values win
    /// — the food form's adopt() precedent); nil means Save mints it.
    private struct PendingComponent: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let portion: String
        let kcal: Double
        let sodiumMg: Double
        let nutrients: NutrientValues
        var matchID: PersistentIdentifier?
        var quantity: Double = 1
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

    /// Foods shown in the picker list; totals still count every selected
    /// food, filtered out of view or not.
    private var visibleFoods: [Food] {
        let trimmed = foodFilter.trimmingCharacters(in: .whitespaces)
        var pool = foods
        // A food a pending component already claims is hidden here: its
        // quantity lives in exactly one place (the review row), so it
        // can't be added twice through two different doors.
        let claimed = Set(pending.compactMap(\.matchID))
        if !claimed.isEmpty {
            pool = pool.filter { !claimed.contains($0.persistentModelID) }
        }
        if !trimmed.isEmpty {
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        // The @Query is name-sorted; the other orders re-sort here (ties
        // break alphabetically, which the stable base order provides).
        let sorted: [Food]
        switch librarySort {
        case .recent:
            sorted = pool.sorted { $0.recencyDate > $1.recencyDate }
        case .name:
            sorted = pool
        }
        // The meal's members lead regardless of sort — what's IN the
        // meal stays visible while adding and editing (the user); the
        // chosen order still applies within each group.
        let inMeal = sorted.filter { (quantities[$0.persistentModelID] ?? 0) > 0 }
        guard !inMeal.isEmpty else { return sorted }
        return inMeal + sorted.filter { (quantities[$0.persistentModelID] ?? 0) == 0 }
    }

    private var totalKcal: Double {
        foods.reduce(0) { $0 + $1.kcal * (quantities[$1.persistentModelID] ?? 0) }
            + pending.reduce(0) { $0 + kcal(of: $1) * $1.quantity }
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
                sodiumMg: sodiumMg(of: component), nutrients: nutrients(of: component)) ?? 0
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

    /// A matched component reads through its LIBRARY food (its values win
    /// — the food form's adopt() precedent, so a saved food's corrected
    /// numbers aren't overwritten by an estimate); a new one reads the
    /// estimate. Same three accessors everywhere, so the Total, the row,
    /// and the save can't disagree.
    private func matchedFood(_ component: PendingComponent) -> Food? {
        guard let id = component.matchID else { return nil }
        return foods.first { $0.persistentModelID == id }
    }
    private func kcal(of component: PendingComponent) -> Double {
        matchedFood(component)?.kcal ?? component.kcal
    }
    private func sodiumMg(of component: PendingComponent) -> Double {
        matchedFood(component)?.sodiumMg ?? component.sodiumMg
    }
    private func nutrients(of component: PendingComponent) -> NutrientValues {
        matchedFood(component)?.nutrients ?? component.nutrients
    }

    var body: some View {
        // Bound once per evaluation, like FoodsView: each access to the
        // computed property re-filters and re-sorts the whole library,
        // and the picker section reads it twice.
        let visibleFoods = visibleFoods
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
                // screen exactly when it was needed).
                LabeledContent("Total") {
                    Text("\(totalKcal, format: .number.precision(.fractionLength(0))) kcal • \(libraryMetric.captionText(totalMetricAmount, sodium: SharedStore.sodiumUnit))")
                        .monospacedDigit()
                        .foregroundStyle(hasItems ? .primary : .secondary)
                }

                // The search field describes a MEAL as readily as it
                // filters foods (one field, the app-wide grammar): the
                // estimate row leads the food list whenever something is
                // typed, and a pick lands in the review section below.
                if !foodFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                    MealEstimateSection(
                        query: foodFilter,
                        isEstimating: $isEstimatingMeal
                    ) { meal in
                        apply(meal)
                    }
                }

                if !pending.isEmpty {
                    pendingSection
                }

                Section {
                    ForEach(visibleFoods) { food in
                        // Quarter-step ± plus a TYPED quantity, exactly
                        // like the portion sheet — half a Soylent belongs
                        // in a meal (the user). The field bypasses the
                        // Stepper's range, so clamp in the binding too.
                        Stepper(value: binding(for: food), in: 0...20, step: 0.25) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                    Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField("—", value: typedBinding(for: food),
                                          format: .number.precision(.fractionLength(0...2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 56)
                                    .monospacedDigit()
                                    .focused($quantityFocused)
                                    .accessibilityLabel("Servings of \(food.name)")
                            }
                            .padding(.trailing, 8)
                        }
                    }
                    if visibleFoods.isEmpty {
                        // `No foods match “”.` rendered for an emptied
                        // library.
                        Text(foodFilter.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "No saved foods yet — add foods to your Food Library first."
                            : "No foods match “\(foodFilter.trimmingCharacters(in: .whitespaces))”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Foods")
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
            // Scoped to quantity changes: a picked food animates up to
            // the members group instead of teleporting.
            .animation(.default, value: quantities)
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

    /// The described meal's parts, awaiting review. Every component shows
    /// with a quantity stepper, its estimated portion, and whether Save
    /// will link an existing food (✓) or mint a new one (✨) — the numbers
    /// are estimates and the section says so, once, in its footer.
    private var pendingSection: some View {
        Section {
            ForEach($pending) { $component in
                Stepper(value: $component.quantity, in: 0...20, step: 0.25) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(component.name)
                                if component.matchID == nil {
                                    Text("✨")
                                        .font(.caption2)
                                        .accessibilityLabel("AI estimate")
                                }
                            }
                            Text(pendingCaption(component))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("—", value: $component.quantity,
                                  format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 56)
                            .monospacedDigit()
                            .focused($quantityFocused)
                            .accessibilityLabel("Servings of \(component.name)")
                    }
                    .padding(.trailing, 8)
                }
            }
            .onDelete { offsets in
                pending.remove(atOffsets: offsets)
            }
        } header: {
            Text("From your description")
        } footer: {
            let minted = pending.count { $0.matchID == nil && $0.quantity > 0 }
            Text(minted == 0
                 ? pendingEngine.estimateCaption
                 : "\(pendingEngine.estimateCaption) Saving adds \(minted == 1 ? "1 food" : "\(minted) foods") to your library.")
        }
    }

    /// A matched row says so (and shows the LIBRARY food's calories, which
    /// is what will be logged); a new one shows the estimated portion.
    private func pendingCaption(_ component: PendingComponent) -> String {
        let kcalText = "\(kcal(of: component).formatted(.number.precision(.fractionLength(0)))) kcal"
        if matchedFood(component) != nil {
            return "\(kcalText) • in your library"
        }
        return component.portion.isEmpty ? kcalText : "\(kcalText) • \(component.portion)"
    }

    /// A described meal lands here: its parts become review rows, matched
    /// against the library first so an existing food is reused rather than
    /// twinned. Nothing is written yet — Save does that.
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
        pending = meal.components.map { component in
            var row = PendingComponent(
                name: component.name, portion: component.portion,
                kcal: component.kcal, sodiumMg: component.sodiumMg,
                nutrients: component.nutrients)
            if let index = ComponentMatch.index(of: component.name, in: names) {
                let food = foods[index]
                row.matchID = food.persistentModelID
                // The review row now owns this food's quantity — leaving
                // a picked quantity behind would count it twice.
                quantities[food.persistentModelID] = 0
            }
            return row
        }
        // The estimate answered the query; leaving it in the field would
        // keep the row (and the filtered food list) up over the review.
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
    ///   change while this sheet is open (a food added on another screen,
    ///   or one deleted out from under a match).
    private func mealItemsFromPending() -> [MealItem] {
        let live = foods
        let names = live.map(\.name)
        var items: [MealItem] = []
        for component in pending where component.quantity > 0 {
            let match = component.matchID.flatMap { id in
                live.first { $0.persistentModelID == id }
            } ?? ComponentMatch.index(of: component.name, in: names).map { live[$0] }
            if let match {
                items.append(MealItem(food: match, quantity: component.quantity))
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

    private func binding(for food: Food) -> Binding<Double> {
        Binding(
            get: { quantities[food.persistentModelID] ?? 0 },
            set: { newValue in
                // The first + selects ONE serving (the default portion),
                // not a quarter of one; ± nudges by quarters from there.
                let old = quantities[food.persistentModelID] ?? 0
                quantities[food.persistentModelID] = (old == 0 && newValue == 0.25) ? 1 : newValue
            }
        )
    }

    /// The typed-quantity flavor: empty shows the "—" placeholder
    /// instead of a wall of zeros, and typed values clamp to the
    /// stepper's range (0.01 minimum — 0 means "not in the meal",
    /// reached by clearing the field).
    private func typedBinding(for food: Food) -> Binding<Double?> {
        Binding(
            get: {
                let quantity = quantities[food.persistentModelID] ?? 0
                return quantity > 0 ? quantity : nil
            },
            set: { newValue in
                guard let newValue, newValue > 0 else {
                    quantities[food.persistentModelID] = 0
                    return
                }
                quantities[food.persistentModelID] = min(newValue, 20)
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
