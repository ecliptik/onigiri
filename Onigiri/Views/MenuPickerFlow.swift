import SwiftUI
import SwiftData
import OnigiriKit

/// One read, several items (`plans/PLAN-multi-item-import.md`).
///
/// A nutrition guide is read once and ordered from several times. Every
/// door that produces a LIST — a photographed menu board, a screenshot
/// holding several foods, a shared guide, a shared page — hands its rows
/// here, and this is what keeps the list alive: pick, confirm, log, land
/// back on the same list with a note saying what went in. The share
/// extension has worked this way since 2026-08-16; the in-app doors threw
/// the read away after the first pick, so a second item cost a second
/// photograph, a second OCR pass and a second run at the model (the user,
/// 2026-08-23).
///
/// It brings no `NavigationStack` of its own — the host owns that, and
/// this contributes the title and the toolbar into it. Two hosts already
/// had a stack each and nesting them would draw two bars.
///
/// The confirm REPLACES the list in the same stack rather than opening
/// over it. That is not the 2026-07-22 sheet race and cannot become it:
/// no sheet is presented, so there is no binding to swap mid-dismissal.
struct MenuPickerFlow: View {
    /// The parsed list. Empty is legal and means a single food arrived
    /// with nothing behind it — `initialPick` then carries it and Log
    /// finishes, because there is no list to come back to.
    let rows: [MenuRow]
    let suggestedSource: String?
    /// A food to confirm immediately, skipping the list: a page that
    /// stated ONE food, or a label read that produced a single panel.
    var initialPick: ParsedLabel?
    let completion: Completion
    let onFinish: (_ logged: Bool) -> Void

    /// What a pick is FOR, which is not the same question in every host.
    enum Completion {
        /// Log it here and come back for the next one, OR save it to the
        /// library without logging and come back for the next one — a
        /// menu is read once and not everything on it is being eaten now
        /// (the user, 2026-08-29). The Log sheet, the shared-image sheet,
        /// the menu import sheet, the share extension.
        case logging(
            saving: LibrarySaving,
            write: (MenuLogRequest) async -> String?,
            saveOnly: (MenuLogRequest) async -> String?
        )
        /// Hand the first pick to the host and stop — the Add Food
        /// form's doors FILL A FORM, they do not log, and a door that
        /// starts writing to Health from inside a form nobody asked to
        /// submit is a different feature.
        case filling((ParsedLabel) -> Void)
    }

    /// Whether the dish also lands in the library, and whether that is
    /// the user's call.
    enum LibrarySaving {
        /// The share extension: no other way to keep the dish, and no
        /// form to keep it from.
        case always
        /// The app: "saving to the library is the option, not the price
        /// of admission" (the user, `QuickLogSheet`). Starts off.
        case optional
    }

    @State private var phase = Phase.picking
    /// Set once, in this view's own `.task` — which runs for the whole
    /// import, unlike `MenuPicker`'s, which remounts every time picking
    /// resumes after a log. Owning it here is what makes "ask once" true
    /// (2026-08-29).
    @State private var source = ""
    @State private var askingSource = false
    @State private var chosen: ParsedLabel?
    /// The row `chosen` came from, so the list can mark what already
    /// went in. Nil for `initialPick`, which came from no row.
    @State private var chosenRowID: Int?
    @State private var logged: [Logged] = []
    /// Reset per item. The MEAL below deliberately is not.
    @State private var quantity = 1.0
    /// Survives every log in this flow: several items off one menu are
    /// one meal, and re-picking "Dinner" each time is the busywork this
    /// screen exists to remove.
    @State private var category = FoodCategory.slot(for: .now)
    @State private var saveToLibrary = false
    /// Which of the confirm's two actions is in flight, if either — this
    /// is what disables both buttons and picks the spinner's word
    /// (`LogConfirmSheet.Busy`).
    @State private var busy: LogConfirmSheet.Busy?
    /// Why the last write didn't take. Shown IN the confirm — a toast
    /// would be behind the host's own sheet.
    @State private var failure: String?

    private enum Phase: Equatable {
        case picking
        /// A menu row that printed no calories, being estimated. Named,
        /// because this is the slow leg and an unnamed spinner over a
        /// list you just tapped reads as a hang.
        case estimating(String)
        case confirming
    }

    private struct Logged {
        let name: String
        let rowID: Int?
        /// Logged to Health, or saved to the library alone — the note
        /// and the row's own mark both need to say which.
        let kind: MenuPickProgress.Kind
    }

    var body: some View {
        content
            .navigationTitle(phase == .confirming ? "Log Food" : "Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { leadingButton }
                if case .confirming = phase, let chosen {
                    ToolbarItemGroup(placement: .confirmationAction) {
                        // Top-right, matching every sheet in the app,
                        // where the committing action is never a row at
                        // the bottom of a form (the user, 2026-08-16).
                        // TWO actions, not one: a menu is read once, and
                        // not everything on it is being eaten right now
                        // — Save keeps the dish without telling Health
                        // you ate it (the user, 2026-08-29).
                        Button("Save") { commitSave(chosen) }
                            .disabled(busy != nil)
                        Button("Log") { commit(chosen) }
                            .disabled(busy != nil)
                    }
                } else if case .picking = phase, !logged.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onFinish(true) }
                    }
                }
            }
            .task {
                source = suggestedSource ?? ""
                // Ask only when the menu didn't say. Detection is the
                // optimisation; this prompt is the contract.
                if suggestedSource == nil { askingSource = true }
                if let initialPick { await choose(initialPick, rowID: nil) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .picking:
            MenuPicker(
                rows: rows,
                note: MenuPickProgress.note(logged.map { .init(name: $0.name, kind: $0.kind) }),
                loggedRowIDs: Set(logged.filter { $0.kind == .logged }.compactMap(\.rowID)),
                savedRowIDs: Set(logged.filter { $0.kind == .saved }.compactMap(\.rowID)),
                source: $source,
                askingSource: $askingSource
            ) { picked, row in
                Task { await choose(picked, rowID: row.id) }
            }
        case .estimating(let name):
            ContentUnavailableView {
                Label("Estimating \(name)…", systemImage: "sparkles")
            } description: {
                ProgressView()
            }
        case .confirming:
            if let chosen {
                LogConfirmSheet(
                    label: chosen,
                    category: $category,
                    quantity: $quantity,
                    saveToLibrary: savingBinding,
                    busy: busy,
                    failure: failure)
            }
        }
    }

    /// Cancel abandons everything; Back returns to a list that is still
    /// there. Picking the wrong row must not cost the read — that is the
    /// whole complaint this screen answers, and Cancel-as-only-exit
    /// would reintroduce it one level down.
    @ViewBuilder
    private var leadingButton: some View {
        if phase != .picking, !rows.isEmpty {
            Button("Back") {
                chosen = nil
                chosenRowID = nil
                failure = nil
                phase = .picking
            }
            .disabled(busy != nil)
        } else {
            Button("Cancel", role: .cancel) { onFinish(!logged.isEmpty) }
                .disabled(busy != nil)
        }
    }

    private var savingBinding: Binding<Bool>? {
        guard case .logging(let saving, _, _) = completion, saving == .optional else { return nil }
        return $saveToLibrary
    }

    // MARK: Choosing

    /// A dish with no calories was LISTED, not measured — so the model
    /// runs for the one item actually being eaten, and only then. A menu
    /// prints thirty dishes; estimating all of them on the way in would
    /// spend inference on twenty-nine answers nobody asked for.
    private func choose(_ picked: ParsedLabel, rowID: Int?) async {
        var label = picked
        if label.kcal == nil, let name = label.name, FoodIntelligence.isAvailable {
            phase = .estimating(name)
            if let described = await FoodIntelligence.describeFood(name) {
                label.kcal = described.kcal
                label.sodiumMg = described.sodiumMg
                label.nutrients = described.nutrients
                if label.servingDescription == nil, !described.serving.isEmpty {
                    label.servingDescription = described.serving
                }
                // A model's numbers, not the menu's — the mark and the
                // review contract travel with them.
                label.aiGenerated = true
            }
        }
        // AI off, or the model declined: hand over what the menu said and
        // nothing more. A half-filled form beats an invented number.
        switch completion {
        case .filling(let hand):
            hand(label)
        case .logging:
            chosen = label
            chosenRowID = rowID
            failure = nil
            phase = .confirming
        }
    }

    // MARK: Logging

    private func commit(_ label: ParsedLabel) {
        guard case .logging(let saving, let write, _) = completion, busy == nil else { return }
        busy = .logging
        Task {
            let problem = await write(MenuLogRequest(
                label: label,
                category: category,
                quantity: quantity,
                saveToLibrary: saving == .always || saveToLibrary))
            busy = nil
            guard problem == nil else {
                failure = problem
                return
            }
            // A single food has no list behind it, so logging it IS the
            // whole errand.
            guard !rows.isEmpty else { return onFinish(true) }
            logged.append(Logged(name: label.name ?? "Menu item", rowID: chosenRowID, kind: .logged))
            chosen = nil
            chosenRowID = nil
            quantity = 1
            phase = .picking
        }
    }

    /// The library keeps the dish; Health never hears about it. Same
    /// shape as `commit`, on purpose — the two differ only in which
    /// closure runs and which `Kind` the row remembers.
    private func commitSave(_ label: ParsedLabel) {
        guard case .logging(_, _, let saveOnly) = completion, busy == nil else { return }
        busy = .saving
        Task {
            let problem = await saveOnly(MenuLogRequest(
                label: label,
                category: category,
                quantity: quantity,
                saveToLibrary: true))
            busy = nil
            guard problem == nil else {
                failure = problem
                return
            }
            guard !rows.isEmpty else { return onFinish(true) }
            logged.append(Logged(name: label.name ?? "Menu item", rowID: chosenRowID, kind: .saved))
            chosen = nil
            chosenRowID = nil
            quantity = 1
            phase = .picking
        }
    }
}

/// One log, as the flow asks for it. A struct rather than four
/// parameters because `saveToLibrary` answers a question the host asked
/// (or didn't), and losing it in an argument list is how the app would
/// quietly start saving everything.
struct MenuLogRequest {
    let label: ParsedLabel
    let category: FoodCategory
    let quantity: Double
    let saveToLibrary: Bool

    /// The name to write, never empty.
    var name: String { label.name ?? "Menu item" }
}

/// Putting a picked dish in the library, for both hosts — the app when
/// the toggle is on, the extension always.
///
/// Deliberately `Food`-only, and that is a safety property rather than a
/// simplification: it never reads `MealItem.food`, the one access that
/// trips the dangling-reference process kill, so it is immune as
/// written. An audit proposed a `repairDanglingFoodReferences`
/// pre-flight here as "cheap insurance" (2026-08-17, declined
/// 2026-08-18) — that pass fetches every Meal and walks `meal.items` and
/// `item.food`, so it would MANUFACTURE the traversal it protects
/// against, and it is only safe after the Core Data pass `OnigiriApp`
/// runs first. Do not give this function a `Meal` fetch.
enum MenuLibrarySave {
    static func insert(_ request: MenuLogRequest, into context: ModelContext) {
        // The app's duplicate rule trims and case-folds; an exact-match
        // predicate did neither, so the same dish with any difference in
        // capitalisation minted a twin (audit, 2026-08-17). `nameMatches`
        // can't be expressed as a `#Predicate` — SwiftData can't compile
        // the trim or the case fold — so the sweep happens here instead,
        // over a hand-entered library.
        let name = request.name
        let existing = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        guard !existing.contains(where: { LibraryDuplicate.nameMatches($0.name, name) })
        else { return }
        let label = request.label
        let food = Food(name: name, kcal: label.kcal ?? 0, sodiumMg: label.sodiumMg ?? 0)
        food.nutrients = label.nutrients
        food.servingDescription = label.servingDescription ?? ""
        food.aiGenerated = label.aiGenerated
        // Recency means LOGGED, never looked at (2026-08-14) — and this
        // runs only from the confirm handler, which a cancel never
        // reaches.
        food.lastUsedAt = .now
        context.insert(food)
        try? context.save()
    }
}
