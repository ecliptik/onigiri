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
    /// The dropbox original backing a drained item. It outlives `take()`
    /// on purpose — an app killed mid-import re-finds the share on the
    /// next foreground instead of losing it (audit, 2026-08-17) — and it
    /// leaves with the sheet, here.
    var inboxOriginal: URL?

    /// Discard the working copy AND the dropbox original. One-shot means
    /// nothing lingers after the sheet that read it.
    func cleanUp() {
        guard isOurs else { return }
        if let inboxOriginal {
            try? FileManager.default.removeItem(at: inboxOriginal)
        }
        switch item {
        case .document(let url), .image(let url):
            try? FileManager.default.removeItem(at: url)
        case .link:
            break
        }
    }
}

/// A whole imported menu, read and then ordered from
/// (`plans/PLAN-menu-import.md`).
///
/// The reading is here; the pick→confirm→log→pick loop is
/// `MenuPickerFlow`, shared with the share extension. This sheet used to
/// stack a full `FoodFormView` over the list per item — reviewable, but
/// four dishes off one guide meant four trips through a form built for
/// creating a food, when what was happening was ordering lunch
/// (`plans/PLAN-multi-item-import.md`).
///
/// One-shot by construction. The document is parsed from memory, never
/// copied in, and nothing survives this sheet except what was logged and
/// any food explicitly saved to the library.
struct MenuImportSheet: View {
    /// `.document` for a PDF, `.link` for a page or PDF URL that has to
    /// be resolved first — the resolve happens inside the reading phase,
    /// so a download and a render look the same to the user.
    let shared: ShareInbox.Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var phase = Phase.reading
    @State private var rows: [MenuRow] = []
    /// One food and no table — a product page stating its nutrition in a
    /// sentence. It goes to the full form, not to the flow's quick
    /// confirm: the quick confirm exists because picking the fourth
    /// dish off a menu should not cost four trips through a form, and a
    /// single food costs one. These numbers are also the riskiest in the
    /// app — read out of prose, where `SharedPageReader` fabricates a
    /// coordinate per line — so the screen that can EDIT them is the
    /// right one (`plans/PLAN-nutrition-plausibility.md`).
    @State private var single: Pick?

    /// A UUID rather than the product: every read here folds to a
    /// barcode-less `ScannedProduct`, so product identity would collapse
    /// two arrivals into one and `.sheet(item:)` would refuse to
    /// re-present the second.
    private struct Pick: Identifiable {
        let id = UUID()
        let product: ScannedProduct
    }
    @State private var detectedSource: String?
    /// The host of a SHARED LINK, when the import came from one — a web
    /// address names the business more reliably than a PDF's metadata.
    @State private var linkHost: String?
    @State private var linkURL: URL?
    @State private var readingStatus = "Looking for nutrition…"

    private enum Phase: Equatable {
        case reading
        case ready
        /// The form is up; this sheet is only its host now.
        case handedOff
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
        }
        .task { await load() }
        .sheet(item: $single, onDismiss: { dismiss() }) { pick in
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
            .navigationTitle("Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelButton }
        case .failed(let message):
            ContentUnavailableView {
                Label("No nutrition found", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
            .navigationTitle("Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelButton }
        case .ready:
            // `.optional`: in the app, saving to the library is the
            // option and not the price of admission (the user) — the
            // extension is the one that always saves, because it has no
            // second visit.
            MenuPickerFlow(
                rows: rows,
                suggestedSource: detectedSource,
                completion: .logging(saving: .optional, write: log, saveOnly: saveOnly),
                onFinish: { _ in dismiss() })
        case .handedOff:
            // Briefly visible behind the form; never a dead end, because
            // dismissing the form dismisses this too.
            Color.clear
        }
    }

    /// Cancel on the left, matching the forms: a menu you opened and
    /// decided against needs a way out that doesn't read as "finished"
    /// (the user). Once the flow is up it owns this slot — and adds Done
    /// beside it as soon as something has been logged.
    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
        }
    }

    private func log(_ request: MenuLogRequest) async -> String? {
        // The app's own log path: toast, undo, haptic, widget reload.
        let ok = await LogActions.logFood(
            name: request.name,
            kcal: (request.label.kcal ?? 0) * request.quantity,
            sodiumMg: (request.label.sodiumMg ?? 0) * request.quantity,
            nutrients: request.label.nutrients.scaled(by: request.quantity),
            category: request.category,
            aiGenerated: request.label.aiGenerated,
            quantity: request.quantity)
        guard ok else { return "Couldn't log that item. Try again." }
        // After the log, and never at the cost of it.
        if request.saveToLibrary { MenuLibrarySave.insert(request, into: context) }
        return nil
    }

    /// The library keeps the dish; nothing goes to Health. A menu is
    /// read once, and not every dish on it is being eaten right now.
    private func saveOnly(_ request: MenuLogRequest) async -> String? {
        MenuLibrarySave.insert(request, into: context)
        return nil
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
                var stated = await SharedPageReader.singleFood(from: document.pages)
                if stated == nil, let linkURL,
                   let text = await MenuLinkLoader.pageText(for: linkURL) {
                    stated = await SharedPageReader.singleFood(fromPageText: text)
                }
                if let stated {
                    // A one-row list is a question with one answer — the
                    // form takes it directly, as it always has.
                    phase = .handedOff
                    single = Pick(product: stated.scannedProduct())
                    return
                }
                var message = "Try a photo or screenshot of one item instead."
                #if DEBUG
                // Which stage gave up — see ShareFlow, which shows the
                // same line.
                message += "\n[dbg runs=\(document.pages.map(\.count)) \(document.scanNote ?? "no ocr")]"
                // AND the transcript, for reading off the device with
                // `xcrun devicectl device copy from --domain-type
                // appDataContainer`. On-device Vision and the
                // simulator's do not produce the same runs, and no
                // amount of reasoning on a Mac substitutes for the
                // phone's own — four builds went to the device before
                // that sank in (2026-08-23). `debugScanned` and not
                // `pages`, because a REJECTED reading is the one worth
                // looking at and `pages` no longer holds it.
                struct Dump: Encodable { let observations: [LabelObservation] }
                let scanned = document.debugScanned?.first ?? document.pages.first ?? []
                if let out = try? JSONEncoder().encode(Dump(observations: scanned)),
                   let dir = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask).first {
                    try? out.write(to: dir.appending(path: "menu-scan-debug.json"))
                }
                #endif
                phase = .failed(message)
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
