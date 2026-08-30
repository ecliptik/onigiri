import SwiftUI
import SwiftData
import UIKit
import OnigiriKit

/// The whole feature, inside the share sheet
/// (`plans/PLAN-menu-import.md`). Read what was shared, show the picker,
/// log the chosen dish — Onigiri never opens.
///
/// A share extension CAN do this; what it cannot do is launch its host
/// app, and those two were conflated when this shipped as a hand-off.
/// Tailscale's device list is the same shape of thing (the user,
/// 2026-08-16).
///
/// The hand-off survives as an AUTOMATIC fallback rather than as a
/// choice: `ShareViewController` deposits into `ShareInbox` BEFORE this
/// view runs and clears the deposit only once something is logged. An
/// extension killed for memory mid-render therefore leaves the document
/// waiting, and the app picks it up on next foreground exactly as it
/// used to.
///
/// Since `plans/PLAN-multi-item-import.md` this view only READS. The
/// pick→confirm→log→pick loop it invented is `MenuPickerFlow`, shared
/// with the app so that the in-app doors stop throwing the read away
/// after one item; what stays here is what only an extension does — the
/// memory-capped decode, the HealthKit authorisation this separate
/// process needs, and its own store.
struct ShareFlow: View {
    let payload: SharePayload
    /// Called once the work is finished (or abandoned) so the host can
    /// complete the extension request.
    let onFinish: (_ logged: Bool) -> Void

    @State private var phase = Phase.reading
    @State private var status = "Reading…"
    @State private var rows: [MenuRow] = []
    /// One food and no table — a product page that states its nutrition
    /// in a sentence. Confirmed straight away; there is no list to come
    /// back to.
    @State private var single: ParsedLabel?
    @State private var suggestedSource: String?
    @State private var linkHost: String?
    @State private var linkURL: URL?
    /// An ESTIMATE waiting to be checked. This is the host that gains
    /// the most from the step: an extension has no food form, so before
    /// it the numbers a photo estimated could only be accepted or
    /// abandoned (`plans/PLAN-refine-with-context.md`).
    @State private var estimate: Estimate?

    private enum Phase: Equatable {
        case reading
        case ready
        case failed(String)
        /// One estimate, with a field to correct it before the confirm.
        case checking
    }

    private struct Estimate: Identifiable {
        let id = UUID()
        let context: RefineContext
    }

    var body: some View {
        NavigationStack {
            content
        }
        .task { await read() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .reading:
            ContentUnavailableView {
                Label(status, systemImage: "doc.text.magnifyingglass")
            } description: {
                ProgressView()
            }
            .navigationTitle("Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onFinish(false) }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("No nutrition found", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
            .navigationTitle("Choose an Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onFinish(false) }
                }
            }
        case .checking:
            if let estimate {
                EstimateRefineStep(
                    context: estimate.context,
                    backTitle: "Cancel",
                    onBack: { onFinish(false) },
                    onUse: { product in
                        single = product.parsedLabel
                        phase = .ready
                    })
            }
        case .ready:
            // `.always`: an extension has no form to save from and no
            // second visit, so a dish LOGGED here is kept unconditionally.
            // `saveOnly` is the extension's answer to "not necessarily
            // log it" (the user, 2026-08-29) — the one door here that has
            // no form and no second visit still needs a way to keep a
            // dish without claiming you ate it.
            MenuPickerFlow(
                rows: rows,
                suggestedSource: suggestedSource,
                initialPick: single,
                completion: .logging(saving: .always, write: log, saveOnly: saveOnly),
                onFinish: onFinish)
        }
    }

    // MARK: Estimate → the confirm's currency

    /// The rendered page first, then the page's own TEXT — which is the
    /// only place a collapsed accordion's figures exist.
    private func singleFoodFromShare(_ document: MenuDocument) async -> ParsedLabel? {
        if let found = await SharedPageReader.singleFood(from: document.pages) { return found }
        guard let linkURL, let text = await MenuLinkLoader.pageText(for: linkURL) else { return nil }
        return await SharedPageReader.singleFood(fromPageText: text)
    }

    // MARK: Reading

    private func read() async {
        switch payload {
        case .document(let url):
            // `temporary: url` — OURS to delete. Every `.document` and
            // `.image` payload is built by `ShareViewController.local`,
            // a scratch copy in this extension's own tmp/, distinct from
            // the `ShareInbox` deposit (which is the app's). Passing nil
            // here left one behind, up to 40 MB, on every document share
            // — and the whole point of the flow is that a guide is
            // shared repeatedly (audit, 2026-08-17). Safe to drop after
            // the read: `rows` holds the parse, so picking a second item
            // never returns to the file.
            await readMenu(at: url, temporary: url)
        case .link(let remote):
            status = "Looking for nutrition…"
            do {
                linkHost = remote.host()
                linkURL = remote
                let rendered = try await MenuLinkLoader.pdf(for: remote)
                await readMenu(at: rendered, temporary: rendered)
            } catch {
                phase = .failed("Couldn't open that link. Try sharing the page again, or share the PDF.")
            }
        case .image(let url):
            await readImage(at: url)
        }
    }

    private func readMenu(at url: URL, temporary: URL?) async {
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        // Read AND parse off the main actor: a big page is ~1,700 text
        // runs, and even fast the work has no business on the thread
        // drawing the spinner.
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (MenuDocument, [MenuRow])? in
            // `readOCR`, matching ScanSheet and MenuImportSheet. Plain
            // `read` returned NOTHING for a rasterised guide — the whole
            // table is artwork, so PDFKit has no runs to hand the parser
            // (Starbucks: 3 pages, 22 runs between them) — and this path
            // then told the user to screenshot it instead, which is not
            // the problem and not the cure. It cost only the share sheet:
            // the same file opened inside the app read fine (audit,
            // 2026-08-17).
            //
            // Affordable here because it renders only pages below
            // `scannedPageRunLimit`, so a text PDF pays nothing, and it
            // is capped at `ocrPageLimit`. And if a huge scanned guide
            // does get this extension jetsammed, the `ShareInbox` deposit
            // outlives it and the app drains it into `MenuImportSheet` —
            // which OCRs. That net is what makes the expensive read safe
            // to attempt from a memory-capped process.
            guard let document = try? await MenuDocumentReader.readOCR(url) else { return nil }
            return (document, MenuTableParser.parse(pages: document.pages))
        }.value
        guard let (document, parsed) = outcome else {
            phase = .failed("Onigiri couldn't open that file.")
            return
        }
        guard !parsed.isEmpty else {
            // No TABLE — but a product page states one food in a
            // sentence, and that is still something to log.
            if let found = await singleFoodFromShare(document) {
                single = found
                phase = .ready
                return
            }
            var message = "Try a photo or screenshot of the nutrition instead."
            #if DEBUG
            // WHICH STAGE GAVE UP, in the one place it can be seen. The
            // read escalates through a whole-page pass, sixteen strip
            // passes and a close look at the header, behind a memory cap
            // and a pass budget — and when it comes back empty nothing
            // on screen says which of those stopped. These counts are
            // what ruled out the extension's memory cap (`strips=8/8`)
            // and Vision itself (`up=469`) on the phone, and pointed at
            // the transcript instead (2026-08-23).
            message += "\n[dbg runs=\(document.pages.map(\.count)) \(document.scanNote ?? "no ocr")]"
            #endif
            phase = .failed(message)
            return
        }
        rows = parsed
        suggestedSource = document.suggestedSource
        // Before the picker appears — see MenuImportSheet: it asks on
        // appear, so the answer has to be there by then.
        if suggestedSource == nil {
            suggestedSource = await FoodIntelligence.readMenuSource(pages: document.pages, host: linkHost)
        }
        phase = .ready
    }

    /// Smaller than the app's 3000: the extension has 220 MB for
    /// EVERYTHING — the decode, Vision, and the model — where the app
    /// has the whole device. 1800 px still OCRs a menu comfortably.
    private static let maxImageEdge: CGFloat = 1800

    private func readImage(at url: URL) async {
        // Same scratch copy, same ownership as the document case above.
        defer { try? FileManager.default.removeItem(at: url) }
        // Decoded once, at size, from the bytes — see
        // UIImage.downsampled(data:maxEdge:). Loading it full-size is
        // what jetsam killed this extension for.
        guard let data = try? Data(contentsOf: url),
              let image = UIImage.downsampled(data: data, maxEdge: Self.maxImageEdge)
        else {
            phase = .failed("Onigiri couldn't open that image.")
            return
        }
        switch await FoodImageReader.read(image, source: .imported, status: { status = $0 }) {
        case .menu(let items, let source):
            rows = items
            suggestedSource = source
            phase = .ready
        case .label(let parsed):
            single = parsed
            phase = .ready
        case .food(let product, let refine):
            if let refine {
                estimate = Estimate(context: refine)
                phase = .checking
            } else {
                single = product.parsedLabel
                phase = .ready
            }
        case .candidates(let list):
            // The same picker a menu gets, and for the same reason it is
            // now the app's only chooser: a list you can return to beats
            // a dialog you cannot (PLAN-multi-item-import).
            rows = MenuRow.list(from: list)
            phase = .ready
        case .nothing(let message):
            phase = .failed(message)
        case .cancelled:
            onFinish(false)
        }
    }

    // MARK: Logging

    /// Returns nil on success, or the reason it failed — `MenuPickerFlow`
    /// shows that in the confirm, where it can be seen.
    private func log(_ request: MenuLogRequest) async -> String? {
        let health = HealthKitService()
        // REQUIRED, and its absence is silent in the worst way: energy
        // rides the correlation unconditionally, but every other
        // nutrient is gated on
        // `authorizationStatus(for:) == .sharingAuthorized`
        // (CorrelationWritePolicy). This is a different process from the
        // app, so with nothing requested here the log lands carrying
        // calories and NOTHING else — no error, no warning, just a
        // stripped entry (2026-08-16, seen on the first real share).
        // Idempotent, and never re-prompts for types already allowed.
        try? await health.requestAuthorization()
        do {
            _ = try await health.logFood(
                name: request.name,
                kcal: (request.label.kcal ?? 0) * request.quantity,
                sodiumMg: (request.label.sodiumMg ?? 0) * request.quantity,
                nutrients: request.label.nutrients.scaled(by: request.quantity),
                category: request.category,
                aiGenerated: request.label.aiGenerated,
                quantity: request.quantity)
        } catch {
            return "Couldn't log to Health: \(error.localizedDescription)"
        }
        // Best effort, and deliberately AFTER the log: the log is what
        // was asked for, and a library write that fails must not lose it.
        // Silent on failure — the store may be open in the app, and a
        // duplicate or a contended write is not worth failing a completed
        // log over.
        if request.saveToLibrary, let container = try? SharedStore.modelContainer() {
            MenuLibrarySave.insert(request, into: ModelContext(container))
        }
        WidgetReloader.reloadNow(kinds: WidgetKinds.phoneLogAffected)
        return nil
    }

    /// The library keeps the dish; Health never hears about it — no
    /// authorisation request, no `logFood`, no widget reload, because
    /// nothing that feeds a burn or intake number changed. Unlike `log`'s
    /// library write, this one is the whole errand rather than a
    /// best-effort extra, so its failure is reported rather than
    /// swallowed.
    private func saveOnly(_ request: MenuLogRequest) async -> String? {
        guard let container = try? SharedStore.modelContainer() else {
            return "Couldn't reach the food library."
        }
        MenuLibrarySave.insert(request, into: ModelContext(container))
        return nil
    }
}


/// An estimate, in the shape the confirm sheet reads. The extension has
/// no food form, so `ParsedLabel` is the only currency it deals in —
/// this is the inline conversion `readImage` used to do, named and
/// carrying the plausibility findings through so `LogConfirmSheet` can
/// still say what was left out and why.
private extension ScannedProduct {
    var parsedLabel: ParsedLabel {
        var label = ParsedLabel()
        label.name = name.isEmpty ? nil : name
        label.kcal = kcal
        label.sodiumMg = sodiumMg
        label.nutrients = nutrients
        label.servingDescription = servingDescription.isEmpty ? nil : servingDescription
        label.aiGenerated = aiGenerated
        label.warnings = warnings
        return label
    }
}
