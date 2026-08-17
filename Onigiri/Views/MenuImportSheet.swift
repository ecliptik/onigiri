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
    @State private var detectedSource: String?
    /// The host of a SHARED LINK, when the import came from one — a web
    /// address names the business more reliably than a PDF's metadata.
    @State private var linkHost: String?
    @State private var linkURL: URL?
    @State private var pick: Pick?
    @State private var picks = 0
    @State private var readingStatus = "Looking for nutrition…"

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
                .navigationTitle("Choose an Item")
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
                Label("No nutrition found", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
        case .ready:
            list
        }
    }

    private var list: some View {
        MenuPicker(rows: rows, suggestedSource: detectedSource) { picked in
            // A fresh id per pick, not one derived from the row: two
            // rows can share a name, and .sheet(item:) would then refuse
            // to re-present for the second.
            picks += 1
            pick = Pick(id: picks, product: picked.scannedProduct())
        }
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
            readingStatus = "Looking for nutrition…"
            do {
                linkHost = remote.host()
                linkURL = remote
                let rendered = try await MenuLinkLoader.pdf(for: remote)
                temporary = rendered
                url = rendered
            } catch {
                phase = .failed("Couldn't open that link. Onigiri needs the page itself — try Share again from the page, or share the PDF.")
                return
            }
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }

        // Read AND parse off the main actor — see ShareFlow.
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> Result<(MenuDocument, [MenuRow]), Error> in
            do {
                let document = try await MenuDocumentReader.readOCR(url)
                return .success((document, MenuTableParser.parse(pages: document.pages)))
            } catch { return .failure(error) }
        }.value

        switch outcome {
        case .failure(let error):
            phase = .failed(Self.message(for: error))
        case .success(let (document, parsed)):
            guard !parsed.isEmpty else {
                var single = await SharedPageReader.singleFood(from: document.pages)
                if single == nil, let linkURL,
                   let text = await MenuLinkLoader.pageText(for: linkURL) {
                    single = await SharedPageReader.singleFood(fromPageText: text)
                }
                if let single {
                    rows = [MenuRow(
                        id: 0, name: single.name ?? "Food", section: nil,
                        serving: single.servingDescription, kcal: single.kcal,
                        sodiumMg: single.sodiumMg, nutrients: single.nutrients,
                        aiGenerated: single.aiGenerated)]
                    detectedSource = detectedSource ?? linkHost.flatMap(MenuDocumentReader.source(fromHost:))
                    phase = .ready
                    return
                }
                phase = .failed("Try a photo or screenshot of one item instead.")
                return
            }
            rows = parsed
            // The PDF's own metadata first — it costs nothing and it is
            // the document SPEAKING. Only when that says nothing does
            // the model read the name out of the text.
            detectedSource = document.suggestedSource
            // BEFORE the picker appears, not after. MenuPicker raises
            // the "Where is this menu from?" dialog from its own
            // .task, so a name that arrives later cannot stop it — the
            // sheet asked about a document that had already said (the
            // user, 2026-08-16). Nothing is waited on when AI is off:
            // readMenuSource returns immediately.
            if detectedSource == nil {
                detectedSource = await FoodIntelligence.readMenuSource(pages: document.pages, host: linkHost)
            }
            phase = .ready
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
