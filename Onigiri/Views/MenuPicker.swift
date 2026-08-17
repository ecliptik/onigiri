import SwiftUI
import OnigiriKit

/// The picker for a parsed menu, wherever it came from — a shared
/// document, a shared page, or a photograph of the board over the counter
/// (`plans/PLAN-menu-import.md`).
///
/// A restaurant publishes every item at once, so this deliberately does
/// NOT reuse the "Which item?" confirmationDialog a screenshot read
/// raises: that control is sized for a handful, and a menu runs to
/// dozens. What makes a long menu usable is the same thing that makes the
/// rest of the app usable — the standard system search field, bottom
/// placement, no custom bar and no auto-focus.
struct MenuPicker: View {
    let rows: [MenuRow]
    /// Prefilled when the document named its restaurant, which is rare.
    let suggestedSource: String?
    /// What has already been logged from this list, when anything has.
    var note: String?
    let onPick: (ParsedLabel) -> Void

    @State private var source = ""
    @State private var askingSource = false
    @State private var query = ""

    var body: some View {
        List {
            // A LIST ROW, not a bar pinned over the list: "Saving as …
            // (STEAK SHACK)" crowded the header and read as chrome
            // rather than as something editable (the user, 2026-08-16).
            Section {
                LabeledContent("Restaurant") {
                    HStack(spacing: 12) {
                        Text(source.isEmpty ? "None" : source)
                            .foregroundStyle(source.isEmpty ? .tertiary : .secondary)
                        Button(source.isEmpty ? "Add" : "Change") { askingSource = true }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                if let note {
                    Label(note, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title ?? "Menu") {
                    ForEach(section.rows) { row in
                        Button { choose(row) } label: { MenuItemRow(row: row) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if visible.isEmpty {
                Text("No items match “\(query)”.")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "Search \(rows.count) items")
        .task {
            source = suggestedSource ?? ""
            // Ask only when the menu didn't say. Detection is the
            // optimisation; this prompt is the contract.
            if suggestedSource == nil { askingSource = true }
        }
        // A dialog, not a field buried in the list: the source is asked
        // once per import and the answer prefixes every name.
        .alert("Where is this menu from?", isPresented: $askingSource) {
            TextField("Restaurant", text: $source)
                .textInputAutocapitalization(.words)
            Button("Use") {}
            Button("Skip", role: .cancel) { source = "" }
        } message: {
            Text("Onigiri couldn't find a name here. What you enter goes after each item, so \"Greek Chicken\" saves as \"Greek Chicken (CAVA)\".")
        }
    }

    private struct MenuSection {
        let title: String?
        let rows: [MenuRow]
    }

    private var visible: [MenuRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedStandardContains(trimmed)
                || ($0.section?.localizedStandardContains(trimmed) ?? false)
        }
    }

    /// Grouped in the order the menu prints, not alphabetically — the
    /// document's own order is information ("BASES" after "CURATED
    /// BOWLS"), and sorting throws it away.
    private var sections: [MenuSection] {
        var titles: [String?] = []
        var grouped: [String?: [MenuRow]] = [:]
        for row in visible {
            if grouped[row.section] == nil { titles.append(row.section) }
            grouped[row.section, default: []].append(row)
        }
        return titles.map { MenuSection(title: $0, rows: grouped[$0] ?? []) }
    }

    /// "Egg White Grill (Chik Fil A)", matching how the library already
    /// reads — "Margarita (Cayman Jack)". The source TRAILS the dish in
    /// brackets rather than leading it behind a dash (the user,
    /// 2026-08-16): the dish is what you scan the list for, so it goes
    /// first, and every existing row is shaped that way already.
    private func choose(_ row: MenuRow) {
        var label = row.parsedLabel
        if !source.isEmpty { label.name = "\(row.name) (\(source))" }
        onPick(label)
    }
}

/// One menu row: the dish, and what logging it would cost — the grammar
/// the "Which item?" dialog already uses.
private struct MenuItemRow: View {
    let row: MenuRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let serving = row.serving {
                    Text(serving)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if let kcal = row.kcal {
                Text("\(kcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A menu READ FROM A PHOTO, presented over whichever door took the
/// picture. A sheet rather than the candidates dialog for the reason
/// above — a board can list dozens.
extension View {
    func menuPhotoPicker(
        _ rows: Binding<[MenuRow]>,
        suggestedSource: String? = nil,
        onPick: @escaping (ParsedLabel) -> Void
    ) -> some View {
        sheet(isPresented: Binding(
            get: { !rows.wrappedValue.isEmpty },
            set: { if !$0 { rows.wrappedValue = [] } })
        ) {
            MenuPhotoSheet(rows: rows.wrappedValue, suggestedSource: suggestedSource) { picked in
                rows.wrappedValue = []
                onPick(picked)
            } onCancel: {
                rows.wrappedValue = []
            }
        }
    }
}

/// Hosts the picker for a PHOTOGRAPHED menu, where a row may carry no
/// calories at all — most restaurants print none, since US labeling
/// binds only chains of 20+ locations.
///
/// So picking is where the estimate happens, and only then: the menu
/// listed thirty dishes and exactly one of them is being eaten.
/// Estimating all thirty on the way in would spend inference on
/// twenty-nine answers nobody asked for.
private struct MenuPhotoSheet: View {
    let rows: [MenuRow]
    let suggestedSource: String?
    /// What has already been logged from this list, when anything has.
    var note: String?
    let onPick: (ParsedLabel) -> Void
    let onCancel: () -> Void

    @State private var estimating: String?

    var body: some View {
        NavigationStack {
            Group {
                if let estimating {
                    ContentUnavailableView {
                        Label("Estimating \(estimating)…", systemImage: "sparkles")
                    } description: {
                        ProgressView()
                    }
                } else {
                    MenuPicker(rows: rows, suggestedSource: suggestedSource, onPick: choose)
                }
            }
            .navigationTitle("Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
        }
    }

    private func choose(_ picked: ParsedLabel) {
        // A menu that PRINTED calories needs no model at all — that is
        // MenuBoardParser's answer and it is exact.
        guard picked.kcal == nil else { return onPick(picked) }
        guard let name = picked.name, FoodIntelligence.isAvailable else {
            // AI off: hand over the name and nothing else. A half-filled
            // form beats a dead end, and it beats an invented number.
            return onPick(picked)
        }
        estimating = name
        Task {
            let described = await FoodIntelligence.describeFood(name)
            estimating = nil
            guard let described else { return onPick(picked) }
            var label = picked
            label.kcal = described.kcal
            label.sodiumMg = described.sodiumMg
            label.nutrients = described.nutrients
            label.servingDescription = described.serving.nilWhenEmpty
            // These are a model's numbers, not the menu's — the mark and
            // the review contract travel with them.
            label.aiGenerated = true
            onPick(label)
        }
    }
}

extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
