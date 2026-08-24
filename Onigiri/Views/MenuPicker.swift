import SwiftUI
import OnigiriKit

/// The picker for a parsed menu, wherever it came from — a shared
/// document, a shared page, or a photograph of the board over the counter
/// (`plans/PLAN-menu-import.md`).
///
/// A restaurant publishes every item at once, so this is a searchable
/// LIST and not a dialog: a "Which item?" confirmationDialog is sized for
/// a handful, a menu runs to dozens, and — since
/// `plans/PLAN-multi-item-import.md` — a dialog has nowhere to say what
/// has already been logged and no way to be returned to. It is now the
/// only chooser in the product: the multi-food screenshot read raises it
/// too, mapped through `MenuRow`. What makes a long menu usable is the
/// same thing that makes the rest of the app usable — the standard
/// system search field, bottom placement, no custom bar and no
/// auto-focus.
struct MenuPicker: View {
    let rows: [MenuRow]
    /// Prefilled when the document named its restaurant, which is rare.
    let suggestedSource: String?
    /// What has already been logged from this list, when anything has
    /// (`MenuPickProgress`).
    var note: String?
    /// Rows already logged in this sitting. The note names the last one
    /// and counts the rest, which after four picks cannot answer "did I
    /// already add the fries" — the row can. Keyed by ID, not name: a
    /// menu section can print "Small" twice.
    var loggedRowIDs: Set<Int> = []
    /// The row rides along with the label because the caller cannot
    /// recover it — by then the source prefix has been applied to the
    /// name, and two rows can carry the same one.
    let onPick: (ParsedLabel, MenuRow) -> Void

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
                        Button { choose(row) } label: {
                            MenuItemRow(row: row, isLogged: loggedRowIDs.contains(row.id))
                        }
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
        onPick(label, row)
    }
}

/// One menu row: the dish, what logging it would cost, and whether it
/// already went in.
private struct MenuItemRow: View {
    let row: MenuRow
    let isLogged: Bool

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
            // A mark, not a disabled row: ordering two of something is a
            // real order, so a logged row stays tappable.
            if isLogged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Already logged")
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
