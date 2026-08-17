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
struct ShareFlow: View {
    let payload: SharePayload
    /// Called once the work is finished (or abandoned) so the host can
    /// complete the extension request.
    let onFinish: (_ logged: Bool) -> Void

    @State private var phase = Phase.reading
    @State private var status = "Reading…"
    @State private var rows: [MenuRow] = []
    /// What has been logged WITHOUT leaving the sheet. A nutrition guide
    /// is read once and ordered from several times — logging one item
    /// and tearing the whole flow down meant re-sharing the document to
    /// add the fries (the user, 2026-08-16).
    @State private var logged: [String] = []
    @State private var suggestedSource: String?
    @State private var linkHost: String?
    @State private var linkURL: URL?
    @State private var chosen: ParsedLabel?
    // Held HERE, not in the confirm view, because the Log button lives in
    // the navigation bar with Cancel — matching every sheet in the app,
    // where the committing action is top-right and never a row at the
    // bottom of a form (the user, 2026-08-16).
    @State private var category = FoodCategory.slot(for: .now)
    @State private var quantity = 1.0
    @State private var logging = false

    private enum Phase: Equatable {
        case reading
        case picking
        case confirming
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { onFinish(false) }
                    }
                    if phase == .picking, !logged.isEmpty {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { onFinish(true) }
                        }
                    }
                    if phase == .confirming, let chosen {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Log") {
                                logging = true
                                Task {
                                    await log(chosen, category: category, quantity: quantity)
                                }
                            }
                            .disabled(logging)
                        }
                    }
                }
        }
        .task { await read() }
    }

    /// The rendered page first, then the page's own TEXT — which is the
    /// only place a collapsed accordion's figures exist.
    private func singleFoodFromShare(_ document: MenuDocument) async -> ParsedLabel? {
        if let found = await SharedPageReader.singleFood(from: document.pages) { return found }
        guard let linkURL, let text = await MenuLinkLoader.pageText(for: linkURL) else { return nil }
        return await SharedPageReader.singleFood(fromPageText: text)
    }

    /// Reads back what just happened, in the list the next choice is
    /// made from — the confirmation and the next step in one place.
    private var loggedNote: String? {
        guard let last = logged.last else { return nil }
        return logged.count == 1
            ? "Logged \(last). Choose another, or tap Done."
            : "Logged \(logged.count) items, last \(last). Choose another, or tap Done."
    }

    private var title: String {
        switch phase {
        case .confirming: "Log Food"
        default: "Choose an Item"
        }
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
        case .failed(let message):
            ContentUnavailableView {
                Label("No nutrition found", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
        case .picking:
            MenuPicker(rows: rows, suggestedSource: suggestedSource, note: loggedNote) { picked in
                Task { await choose(picked) }
            }
        case .confirming:
            if let chosen {
                ShareLogSheet(
                    label: chosen, category: $category,
                    quantity: $quantity, logging: logging)
            }
        }
    }

    // MARK: Reading

    private func read() async {
        switch payload {
        case .document(let url):
            await readMenu(at: url, temporary: nil)
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
            if let single = await singleFoodFromShare(document) {
                chosen = single
                phase = .confirming
                return
            }
            phase = .failed("Try a photo or screenshot of the nutrition instead.")
            return
        }
        rows = parsed
        suggestedSource = document.suggestedSource
        // Before .picking — see MenuImportSheet: the picker asks on
        // appear, so the answer has to be there by then.
        if suggestedSource == nil {
            suggestedSource = await FoodIntelligence.readMenuSource(pages: document.pages, host: linkHost)
        }
        phase = .picking
    }

    /// Smaller than the app's 3000: the extension has 220 MB for
    /// EVERYTHING — the decode, Vision, and the model — where the app
    /// has the whole device. 1800 px still OCRs a menu comfortably.
    private static let maxImageEdge: CGFloat = 1800

    private func readImage(at url: URL) async {
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
            phase = .picking
        case .label(let parsed):
            await choose(parsed)
        case .food(let product):
            var label = ParsedLabel()
            label.name = product.name.isEmpty ? nil : product.name
            label.kcal = product.kcal
            label.sodiumMg = product.sodiumMg
            label.nutrients = product.nutrients
            label.servingDescription = product.servingDescription.isEmpty
                ? nil : product.servingDescription
            label.aiGenerated = product.aiGenerated
            await choose(label)
        case .candidates(let list):
            // Few enough for the dialog in the app; here the same picker
            // serves, and one control is better than two.
            rows = list.enumerated().map { index, label in
                MenuRow(
                    id: index, name: label.name ?? "Item",
                    serving: label.servingDescription, kcal: label.kcal,
                    sodiumMg: label.sodiumMg, nutrients: label.nutrients)
            }
            phase = .picking
        case .nothing(let message):
            phase = .failed(message)
        case .cancelled:
            onFinish(false)
        }
    }

    // MARK: Choosing and logging

    private func choose(_ picked: ParsedLabel) async {
        // A dish with no calories was LISTED, not measured — estimate the
        // one actually being eaten, exactly as the app does.
        guard picked.kcal == nil, let name = picked.name,
              FoodIntelligence.isAvailable else {
            chosen = picked
            phase = .confirming
            return
        }
        status = "Estimating \(name)…"
        phase = .reading
        var label = picked
        if let described = await FoodIntelligence.describeFood(name) {
            label.kcal = described.kcal
            label.sodiumMg = described.sodiumMg
            label.nutrients = described.nutrients
            if label.servingDescription == nil, !described.serving.isEmpty {
                label.servingDescription = described.serving
            }
            label.aiGenerated = true
        }
        chosen = label
        phase = .confirming
    }

    private func log(_ label: ParsedLabel, category: FoodCategory, quantity: Double) async {
        let name = label.name ?? "Menu item"
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
                name: name,
                kcal: (label.kcal ?? 0) * quantity,
                sodiumMg: (label.sodiumMg ?? 0) * quantity,
                nutrients: label.nutrients.scaled(by: quantity),
                category: category,
                aiGenerated: label.aiGenerated,
                quantity: quantity)
        } catch {
            phase = .failed("Couldn't log to Health: \(error.localizedDescription)")
            return
        }
        // Best effort, and deliberately AFTER the log: the log is what
        // was asked for, and a library write that fails must not lose it.
        saveToLibrary(label, name: name)
        WidgetReloader.reloadNow(kinds: WidgetKinds.phoneLogAffected)
        // Back to the LIST when there is one to go back to. A photo or a
        // label has nothing behind it, so that still finishes.
        guard !rows.isEmpty else { return onFinish(true) }
        logged.append(name)
        chosen = nil
        // Portion resets; the MEAL does not. Several items logged off
        // one menu are one meal, and re-picking "Dinner" each time is
        // the busywork this change exists to remove.
        self.quantity = 1
        logging = false
        phase = .picking
    }

    /// Adds the dish to the library so it is one tap next time. Silent on
    /// failure — the store may be open in the app, and a duplicate or a
    /// contended write is not worth failing a completed log over.
    private func saveToLibrary(_ label: ParsedLabel, name: String) {
        guard let container = try? SharedStore.modelContainer() else { return }
        let context = ModelContext(container)
        // The app's duplicate rule trims and case-folds; an exact-match
        // predicate did neither, so sharing the same dish twice with any
        // difference in capitalisation minted a twin (audit,
        // 2026-08-17). `nameMatches` can't be expressed as a `#Predicate`
        // — SwiftData can't compile the trim or the case fold — so the
        // sweep happens here instead, over a hand-entered library.
        let existing = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        guard !existing.contains(where: { LibraryDuplicate.nameMatches($0.name, name) })
        else { return }
        let food = Food(name: name, kcal: label.kcal ?? 0, sodiumMg: label.sodiumMg ?? 0)
        food.nutrients = label.nutrients
        food.servingDescription = label.servingDescription ?? ""
        food.aiGenerated = label.aiGenerated
        food.lastUsedAt = .now
        context.insert(food)
        try? context.save()
    }
}

/// The last step: what is about to be logged, which meal it belongs to,
/// and how many. Deliberately not the app's whole food form — an
/// extension is a moment, not a workspace. The committing action is NOT
/// here; it sits in the navigation bar beside Cancel, where the app puts
/// Save.
private struct ShareLogSheet: View {
    let label: ParsedLabel
    @Binding var category: FoodCategory
    @Binding var quantity: Double
    let logging: Bool

    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults)
    private var sodiumUnitRaw = SharedStore.unitAutomatic
    private var sodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnitRaw) }

    /// The gate's verdict on one row, when it had one to give
    /// (`NutritionPlausibility`). Suspect values are shown and marked;
    /// impossible ones are already gone, and are named in the footer.
    private func suspect(_ id: String) -> NutritionPlausibility.Finding? {
        label.warnings.first { $0.severity == .suspect && $0.field.rawValue == id }
    }

    /// The findings that have no row to sit beside: what was removed,
    /// and an energy figure its own macros contradict.
    private var notes: [String] {
        label.warnings.compactMap { finding in
            switch finding.severity {
            case .dropped:
                "\(finding.field.displayName) was left out — \(finding.reason)"
            case .suspect:
                finding.field == .energy ? finding.reason : nil
            }
        }
    }

    /// Everything the Log button is about to write, scaled to the
    /// portion — the RECEIPT for it.
    ///
    /// This sheet showed the name, the calories and the serving while
    /// `logFood` wrote sodium and five macros beside them, so a figure
    /// read wrongly off a page could not be caught before it was in
    /// Health: a shared product page logged 810,400 mg of sodium and the
    /// only place that number ever appeared was the log itself
    /// (2026-08-16, `plans/PLAN-nutrition-plausibility.md`). One button,
    /// one write, one list — a value not shown here is a value nobody
    /// agreed to.
    private var written: [(id: String, name: String, amount: String)] {
        var rows: [(String, String, String)] = []
        func add(_ id: String, _ name: String, _ value: Double?, _ unit: String,
                 digits: ClosedRange<Int> = 0...1) {
            guard let value else { return }
            rows.append((id, name,
                "\(value.formatted(.number.precision(.fractionLength(digits)))) \(unit)"))
        }
        if let sodiumMg = label.sodiumMg {
            let digits = sodiumUnit.fractionDigits
            add("sodium", sodiumUnit.nutrientName, sodiumUnit.fromMg(sodiumMg * quantity),
                sodiumUnit.symbol, digits: digits...digits)
        }
        let n = label.nutrients.scaled(by: quantity)
        add("fat", "Fat", n.fatG, "g")
        add("saturatedFat", "Saturated fat", n.saturatedFatG, "g")
        add("transFat", "Trans fat", n.transFatG, "g")
        add("polyunsaturatedFat", "Polyunsaturated fat", n.polyunsaturatedFatG, "g")
        add("monounsaturatedFat", "Monounsaturated fat", n.monounsaturatedFatG, "g")
        add("cholesterol", "Cholesterol", n.cholesterolMg, "mg")
        add("carbs", "Carbohydrates", n.carbsG, "g")
        add("fiber", "Fiber", n.fiberG, "g")
        add("sugar", "Sugar", n.sugarG, "g")
        add("protein", "Protein", n.proteinG, "g")
        add("caffeine", "Caffeine", n.caffeineMg, "mg")
        for micro in Micronutrient.allCases {
            add(micro.rawValue, micro.displayName, n[micro], micro.unit.symbol)
        }
        return rows
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(label.name ?? "Menu item") {
                    if let kcal = label.kcal {
                        Text("\((kcal * quantity).formatted(.number.precision(.fractionLength(0)))) kcal")
                            .monospacedDigit()
                    }
                }
                if let serving = label.servingDescription {
                    LabeledContent("Serving", value: serving)
                }
                if label.aiGenerated {
                    Label("Estimated — review before logging", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if written.isEmpty {
                    Text("Calories only — nothing else was published for this item.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(written, id: \.id) { row in
                        LabeledContent(row.name) {
                            HStack(spacing: 6) {
                                if suspect(row.id) != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                                Text(row.amount).monospacedDigit()
                            }
                        }
                        if let reason = suspect(row.id)?.reason {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Also logged")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everything Onigiri will write to Health, for this portion.")
                    // What was REMOVED has to be said too: a figure
                    // silently dropped and a figure never read look
                    // identical here, and only one of them means the
                    // page said something Onigiri refused to believe.
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                    }
                }
            }
            Section {
                Picker("Meal", selection: $category) {
                    ForEach(FoodCategory.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
                }
                Stepper(
                    "Quantity \(quantity.formatted(.number.precision(.fractionLength(0...2))))",
                    value: $quantity, in: 0.25...20, step: 0.25)
            }
            if logging {
                Section {
                    HStack { ProgressView(); Text("Logging…") }
                }
            }
        }
        .disabled(logging)
    }
}
