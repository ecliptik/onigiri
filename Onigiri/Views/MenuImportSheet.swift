import SwiftUI
import OnigiriKit

/// Something handed to the app from outside, waiting to be read.
/// Identified per arrival so sharing the same thing twice re-presents.
struct SharedImport: Identifiable {
    let id = UUID()
    let item: ShareInbox.Item
    /// True for anything drained out of `ShareInbox` — OUR copy, ours to
    /// delete when the sheet closes. False for a file opened in place
    /// from Files, which belongs to the user and must survive being read.
    var isOurs = false

    /// Discard the working copy. One-shot means nothing lingers after
    /// the sheet that read it.
    func cleanUp() {
        guard isOurs else { return }
        switch item {
        case .document(let url), .image(let url):
            try? FileManager.default.removeItem(at: url)
        case .link:
            break
        }
    }
}

/// The picker for a whole imported menu (`plans/PLAN-menu-import.md`).
///
/// A restaurant publishes every item at once — the Kwik Trip guide runs
/// to 113 rows — so this deliberately does NOT reuse the "Which item?"
/// confirmationDialog a screenshot read raises. That control is sized for
/// a handful. What makes a long menu usable is the same thing that makes
/// the rest of the app usable: the standard system search field, bottom
/// placement, no custom bar and no auto-focus.
///
/// One-shot by construction. The document is parsed from memory, never
/// copied in, and nothing survives this sheet except a food the user
/// actually saved — which lands in the library and reaches Recent and
/// Favorites by the ordinary route.
struct MenuImportSheet: View {
    /// `.document` for a PDF, `.link` for a page or PDF URL that has to
    /// be resolved first — the resolve happens inside the reading phase,
    /// so a download and a render look the same to the user.
    let shared: ShareInbox.Item

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.reading
    @State private var rows: [MenuRow] = []
    @State private var source = ""
    @State private var askingSource = false
    @State private var query = ""
    @State private var pick: Pick?
    @State private var readingStatus = "Reading the menu…"

    private enum Phase: Equatable {
        case reading
        case ready
        case failed(String)
    }

    /// Identified by the ROW, not by the product: every menu row folds to
    /// a barcode-less ScannedProduct, so product identity would collapse
    /// all 113 into one and the form would refuse to re-present.
    private struct Pick: Identifiable {
        let id: Int
        let product: ScannedProduct
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add from Menu")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Cancel on the left beside Done, matching the forms:
                    // a menu you opened and decided against needs a way
                    // out that doesn't read as "finished" (the user).
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await load() }
        // A dialog, not a form field buried in the list: the source is
        // asked once per import and the answer prefixes every name.
        .alert("Where is this menu from?", isPresented: $askingSource) {
            TextField("Restaurant", text: $source)
                .textInputAutocapitalization(.words)
            Button("Use") {}
            Button("Skip", role: .cancel) { source = "" }
        } message: {
            Text("Onigiri couldn't find a name in this document. What you enter goes in front of each item, so \"Greek Chicken\" saves as \"Kwik Trip — Greek Chicken\".")
        }
        .sheet(item: $pick) { pick in
            FoodFormView(food: nil, prefill: pick.product)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .reading:
            ContentUnavailableView {
                Label(readingStatus, systemImage: "doc.text.magnifyingglass")
            } description: {
                ProgressView()
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read that menu", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
        case .ready:
            list
        }
    }

    private var list: some View {
        List {
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
        .safeAreaInset(edge: .top) { sourceBanner }
    }

    /// The source is editable after the fact too — a detected name can
    /// be wrong, and retyping it beats re-importing.
    @ViewBuilder
    private var sourceBanner: some View {
        if !source.isEmpty {
            HStack {
                Text("Saving as")
                    .foregroundStyle(.secondary)
                Text("\(source) — …")
                    .fontWeight(.medium)
                Spacer()
                Button("Change") { askingSource = true }
                    .font(.subheadline)
            }
            .font(.footnote)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
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

    private func choose(_ row: MenuRow) {
        let name = source.isEmpty
            ? row.name
            : "\(source) — \(row.name)"
        pick = Pick(id: row.id, product: row.parsedLabel.scannedProduct(name: name))
    }

    private func load() async {
        // A shared LINK becomes a PDF first: downloaded when the link is
        // one, rendered through a web view when it's a page. Either way
        // the parser below sees the same thing.
        var temporary: URL?
        let url: URL
        switch shared {
        case .document(let local), .image(let local):
            url = local
        case .link(let remote):
            readingStatus = "Processing menu…"
            do {
                let rendered = try await MenuLinkLoader.pdf(for: remote)
                temporary = rendered
                url = rendered
            } catch {
                phase = .failed("Couldn't open that link. Onigiri needs the page itself — try Share again from the page, or share the PDF.")
                return
            }
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }

        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<MenuDocument, Error> in
            do { return .success(try MenuDocumentReader.read(url)) } catch { return .failure(error) }
        }.value

        switch outcome {
        case .failure(let error):
            phase = .failed(Self.message(for: error))
        case .success(let document):
            let parsed = MenuTableParser.parse(pages: document.pages)
            guard !parsed.isEmpty else {
                phase = .failed("No nutrition table in that document. A menu with pictures instead of a table can't be read this way — a screenshot of one item still can, from Foods.")
                return
            }
            rows = parsed
            source = document.suggestedSource ?? ""
            phase = .ready
            // Ask only when the document didn't say. Detection is the
            // optimisation; this prompt is the contract.
            if document.suggestedSource == nil { askingSource = true }
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case MenuDocumentReader.Failure.tooLarge:
            "That file is too big to read as a menu."
        case MenuDocumentReader.Failure.notADocument:
            "That doesn't look like a PDF."
        default:
            "Onigiri couldn't open that file."
        }
    }
}

/// One menu row: the dish, and what logging it would cost — the grammar
/// the "Which item?" dialog already uses.
private struct MenuItemRow: View {
    let row: MenuRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.name)
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
