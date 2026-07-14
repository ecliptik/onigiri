import SwiftUI
import OnigiriKit

/// Shared machinery for searching OpenFoodFacts from any screen: submit-
/// triggered search, with the full product fetched lazily per visible row —
/// the search index has no nutrition fields, and calories + serving on the
/// row disambiguate same-named hits. The cached fetch is reused on pick.
@Observable
@MainActor
final class OnlineFoodSearch {
    private(set) var results: [OpenFoodFactsClient.SearchResult] = []
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var message: String?
    /// Shown below the rows when paging stopped early (throttled).
    private(set) var moreMessage: String?
    private(set) var products: [String: ScannedProduct] = [:]
    private(set) var detailFailures: Set<String> = []
    private(set) var fetchingCode: String?
    /// One in-flight fetch per barcode; picking a row mid-fetch awaits
    /// the existing task instead of firing a duplicate request.
    private var detailTasks: [String: Task<ScannedProduct?, Never>] = [:]
    /// Per-source paging: in Both mode the two lists advance
    /// independently (one can run dry while the other keeps going).
    private var offPage = 1
    private var offHasMore = false
    private var fdcPage = 1
    private var fdcHasMore = false
    private var hasMore: Bool { offHasMore || fdcHasMore }
    /// Barcodes whose product carries no calorie data at all — weeded
    /// from results (useless for logging) and kept out of later pages.
    /// A literal 0 kcal stays: that's real data (water, diet soda).
    /// Reset per search: the client's product cache makes re-weeding a
    /// re-searched barcode free, and retaining the set made a re-search
    /// of a data-poor query dead-end on an empty, fetchless list.
    private var rejected: Set<String> = []
    /// Weeding can chain page loads with zero user input (page → details
    /// → all weeded → next page…) — cap the automatic backfills between
    /// user gestures or a data-poor query can burn the whole rate limit.
    private var autoBackfills = 0
    private static let maxAutoBackfills = 2

    /// The re-rank pool: one search request either way, and the server
    /// orders by scan-count popularity, so a plain "Grapes" can sit
    /// thirty deep under jelly and soda — a bigger page gives the
    /// intent-ranking something to find. Per-row detail fetches are
    /// visible-rows-only, so this doesn't multiply follow-up requests.
    private static let pageSize = 30
    private let client = OpenFoodFactsClient()
    /// Which sources this search runs on, snapshotted per search
    /// (setting + key can change mid-session), so paging stays on the
    /// sources — and the key — the results came from.
    private var mode: SharedStore.TextSearchMode = .openFoodFacts
    private var fdcClient: FoodDataCentralClient?
    /// Rows carry an OFF/FDC tag only when one list mixes both.
    var showsSourceTags: Bool { mode == .both }
    private(set) var lastQuery = ""
    /// Comparing query strings can't tell a resubmit from the search it
    /// supersedes; the generation counter can (same idiom as TodayModel).
    private var searchGeneration = 0
    /// The running search and page load, kept so a resubmit can CANCEL
    /// them — the generation guard already discards stale results, but an
    /// abandoned task's retries kept spending the shared rate limit.
    private var searchTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?

    var hasSearched: Bool { !lastQuery.isEmpty }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        // Kill the superseded search's in-flight requests and pending
        // retries — they'd spend the rate limit on discarded results.
        searchTask?.cancel()
        pageTask?.cancel()
        // Re-read the setting per search, not per session — flipping the
        // source (or fixing the key) in Settings applies to the next
        // search without relaunching.
        mode = SharedStore.textSearchMode
        fdcClient = mode == .openFoodFacts
            ? nil
            : FoodDataCentralClient(apiKey: SharedStore.fdcAPIKey)
        lastQuery = trimmed
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        // A superseded page load never resets this itself — the search
        // that superseded it must, or paging wedges on a stuck spinner.
        isLoadingMore = false
        message = nil
        moreMessage = nil
        results = []
        offPage = 1
        offHasMore = false
        fdcPage = 1
        fdcHasMore = false
        autoBackfills = 0
        rejected = []
        let task = Task { await performSearch(trimmed, generation: generation) }
        searchTask = task
        await task.value
    }

    /// One source's page attempt: its rows, whether a full page came
    /// back (= maybe more), and its error when the leg failed.
    private struct Leg {
        var hits: [OpenFoodFactsClient.SearchResult] = []
        var fullPage = false
        var error: Error?
        var ran = false
    }

    private func performSearch(_ query: String, generation: Int) async {
        var legs: [Leg] = []
        if mode == .both {
            // Each leg renders the moment it lands. Awaiting both let
            // OFF's retry ladder (three 15 s timeouts on a bad day) hold
            // FDC's rows hostage — the device showed 30 s of spinner and
            // then never the merged list.
            await withTaskGroup(of: (isFDC: Bool, leg: Leg).self) { group in
                group.addTask { (true, await self.fetchFDCLeg(query: query, page: 1, generation: generation)) }
                group.addTask { (false, await self.fetchOFFLeg(query: query, page: 1)) }
                for await (isFDC, leg) in group {
                    guard generation == searchGeneration else { return }
                    if isFDC { fdcHasMore = leg.fullPage } else { offHasMore = leg.fullPage }
                    legs.append(leg)
                    // Merge-and-rank everything seen so far; the late
                    // leg folds into the ranked list when it arrives.
                    let combined = OpenFoodFactsClient.rank(
                        legs.flatMap(\.hits), query: query, name: \.name, brand: \.brand
                    ).filter { !rejected.contains($0.barcode) }
                    if !combined.isEmpty {
                        results = combined
                        isSearching = false
                    }
                }
            }
        } else {
            let (fdc, off) = await fetchLegs(query: query, offPage: 1, fdcPage: 1, generation: generation)
            guard generation == searchGeneration else { return } // superseded
            offHasMore = off.fullPage
            fdcHasMore = fdc.fullPage
            legs = [fdc, off].filter(\.ran)
            results = (fdc.hits + off.hits).filter { !rejected.contains($0.barcode) }
        }
        guard generation == searchGeneration else { return }
        let errors = legs.compactMap(\.error)
        if let first = errors.first, results.isEmpty {
            // Every leg that ran failed — toast it (hosts on each
            // sheet); the inline message stays for result states.
            ToastCenter.shared.show(
                first is OpenFoodFactsError || first is FoodDataCentralError
                    ? first.localizedDescription
                    : "Online search failed: \(first.localizedDescription)"
            )
        } else if let partial = errors.first {
            // One leg delivered, the other didn't — the rows are real,
            // the gap deserves naming.
            moreMessage = partial.localizedDescription
        } else if results.isEmpty {
            message = "No \(sourceDisplayName) matches — try different words."
        }
        isSearching = false
    }

    private var sourceDisplayName: String {
        switch mode {
        case .openFoodFacts: "OpenFoodFacts"
        case .fdc: "FDC"
        case .both: "online"
        }
    }

    /// Fetches the requested page of every active source, concurrently
    /// in Both mode. FDC hits carry their nutrients inline — each lands
    /// in `products` up front, so the per-row lazy detail (and the
    /// missing-calories weeding built around it) short-circuits: no
    /// fetch, no weed.
    private func fetchLegs(
        query: String, offPage: Int?, fdcPage: Int?, generation: Int
    ) async -> (fdc: Leg, off: Leg) {
        let runOFF = mode != .fdc && offPage != nil
        let runFDC = fdcClient != nil && fdcPage != nil
        async let offLeg: Leg = runOFF ? fetchOFFLeg(query: query, page: offPage ?? 1) : Leg()
        async let fdcLeg: Leg = runFDC ? fetchFDCLeg(query: query, page: fdcPage ?? 1, generation: generation) : Leg()
        return await (fdcLeg, offLeg)
    }

    private func fetchOFFLeg(query: String, page: Int) async -> Leg {
        var leg = Leg(ran: true)
        do {
            leg.hits = try await client.search(query: query, limit: Self.pageSize, page: page)
            leg.fullPage = leg.hits.count == Self.pageSize
        } catch {
            leg.error = error
        }
        return leg
    }

    private func fetchFDCLeg(query: String, page: Int, generation: Int) async -> Leg {
        var leg = Leg(ran: true)
        guard let fdcClient else { return leg }
        do {
            let foods = try await fdcClient.search(query: query, limit: Self.pageSize, page: page)
            // A superseded search must not seed the new search's products.
            guard generation == searchGeneration else { return leg }
            leg.hits = foods.map { food in
                let product = food.per100gProduct
                products[product.barcode] = product
                return .init(barcode: product.barcode, name: food.description, brand: food.dataType)
            }
            leg.fullPage = foods.count == Self.pageSize
        } catch {
            leg.error = error
        }
        return leg
    }

    /// The next page, triggered when the last row scrolls into view (or,
    /// capped, by weeding — `auto`). A full page means there may be
    /// another; a short/empty page — or a throttle — ends paging until
    /// the next fresh search.
    func loadMore(auto: Bool = false) async {
        guard hasMore, !isSearching, !isLoadingMore, hasSearched else { return }
        if auto {
            guard autoBackfills < Self.maxAutoBackfills else {
                // Out of automatic budget with nothing left to show —
                // say so, or the section is a silent dead end (there are
                // no rows whose scroll could pull the next page).
                if results.isEmpty {
                    message = "Only products without calorie data so far — try different words."
                }
                return
            }
            autoBackfills += 1
        } else {
            // A real user gesture re-arms the automatic backfill.
            autoBackfills = 0
        }
        let query = lastQuery
        let generation = searchGeneration
        isLoadingMore = true
        let task = Task { await performLoadMore(query: query, generation: generation) }
        pageTask = task
        await task.value
    }

    private func performLoadMore(query: String, generation: Int) async {
        let (fdc, off) = await fetchLegs(
            query: query,
            offPage: offHasMore ? offPage + 1 : nil,
            fdcPage: fdcHasMore ? fdcPage + 1 : nil,
            generation: generation
        )
        guard generation == searchGeneration else { return } // superseded
        // A leg's page advances only when it delivered; an errored leg
        // stops paging (its rows so far stand).
        if off.ran {
            if off.error == nil { offPage += 1 }
            offHasMore = off.error == nil && off.fullPage
        }
        if fdc.ran {
            if fdc.error == nil { fdcPage += 1 }
            fdcHasMore = fdc.error == nil && fdc.fullPage
        }
        if let error = [fdc.error, off.error].compactMap({ $0 }).first {
            // Both sources' busy copy is actionable ("wait a minute") —
            // pass it through; everything else collapses to one line.
            moreMessage = (error as? OpenFoodFactsError)?.isBusy == true
                    || (error as? FoodDataCentralError)?.isBusy == true
                ? error.localizedDescription
                : "Couldn't load more results."
        }
        // Rank only the incoming batch — re-ranking the whole list would
        // reshuffle rows under the user's finger.
        let incoming = mode == .both
            ? OpenFoodFactsClient.rank(fdc.hits + off.hits, query: query, name: \.name, brand: \.brand)
            : fdc.hits + off.hits
        // OFF pages can shift between requests — drop repeats (and
        // anything already weeded for missing calories).
        let known = Set(results.map(\.barcode))
        let fresh = incoming.filter { !known.contains($0.barcode) && !rejected.contains($0.barcode) }
        if fresh.isEmpty, !incoming.isEmpty {
            offHasMore = false
            fdcHasMore = false
        }
        results += fresh
        isLoadingMore = false
    }

    func clear() {
        searchTask?.cancel()
        pageTask?.cancel()
        lastQuery = ""
        searchGeneration += 1
        results = []
        message = nil
        moreMessage = nil
        isSearching = false
        isLoadingMore = false
        offPage = 1
        offHasMore = false
        fdcPage = 1
        fdcHasMore = false
        rejected = []
        autoBackfills = 0
    }

    /// Unstructured on purpose: the row's .task would cancel the fetch
    /// when the row scrolls off, then fetch again when it scrolls back.
    /// One in-flight request per barcode, and it runs to completion.
    func loadDetail(for barcode: String) {
        guard products[barcode] == nil, !detailFailures.contains(barcode),
              detailTasks[barcode] == nil else { return }
        detailTasks[barcode] = Task {
            defer { detailTasks[barcode] = nil }
            // The client answers repeats from its process-wide cache, so
            // a re-searched barcode costs no request here.
            let product = try? await client.product(barcode: barcode)
            if let product {
                apply(product, for: barcode)
            } else {
                detailFailures.insert(barcode)
            }
            return product
        }
    }

    private func apply(_ product: ScannedProduct, for barcode: String) {
        products[barcode] = product
        // No calorie data at all — weed it, and backfill a page if
        // weeding emptied the list (bounded; see maxAutoBackfills).
        if product.kcal == nil {
            rejected.insert(barcode)
            results.removeAll { $0.barcode == barcode }
            if results.isEmpty, hasMore, !isSearching {
                // Guard against a stale backfill queued for a superseded
                // query spending the new query's budget.
                let generation = searchGeneration
                Task {
                    guard generation == searchGeneration else { return }
                    await loadMore(auto: true)
                }
            }
        }
    }

    /// "Source: [OpenFoodFacts](…)" markdown for the results footer —
    /// each link opens the same search on the database's own site, so
    /// the data's provenance is one tap away.
    var provenanceLine: String? {
        guard hasSearched else { return nil }
        let encoded = lastQuery.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? lastQuery
        let off = "[OpenFoodFacts](https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&action=process)"
        let fdc = "[FDC](https://fdc.nal.usda.gov/food-search/?query=\(encoded))"
        switch mode {
        case .openFoodFacts: return "Source: \(off)"
        case .fdc: return "Source: \(fdc)"
        case .both: return "Sources: \(fdc) · \(off)"
        }
    }

    /// The full product for a picked row — the cached fetch, the one
    /// already in flight for the row, else a live one, else the bare
    /// search hit (better than nothing).
    func product(for result: OpenFoodFactsClient.SearchResult) async -> ScannedProduct {
        // FDC rows already hold per-100 g values; picking upgrades to the
        // food's household portion ("1 cup, seedless (151 g)") with one
        // detail fetch, cached process-wide alongside OFF lookups.
        if let fdcClient, let base = products[result.barcode],
           FoodDataCentralClient.fdcId(fromCode: result.barcode) != nil {
            fetchingCode = result.barcode
            defer { fetchingCode = nil }
            return await fdcClient.pickedProduct(for: base)
        }
        if let cached = products[result.barcode] { return cached }
        fetchingCode = result.barcode
        defer { fetchingCode = nil }
        // Picking a row the instant it appears used to double-fetch: the
        // row's detail task was still running — await it instead. If that
        // task FAILED, don't immediately double down on the rate limit;
        // fall through to the bare search hit.
        if let running = detailTasks[result.barcode] {
            if let product = await running.value { return product }
        } else if !detailFailures.contains(result.barcode),
                  let product = try? await client.product(barcode: result.barcode) {
            products[result.barcode] = product
            return product
        }
        return ScannedProduct(
            barcode: result.barcode,
            name: result.brand.map { "\(result.name) (\($0))" } ?? result.name,
            kcal: nil,
            sodiumMg: nil,
            servingDescription: "",
            nutrients: NutrientValues()
        )
    }
}

/// Identifiable wrapper so a fetched product can drive `.sheet(item:)`
/// (the prefilled food form for new-food logging).
struct ProductPrefill: Identifiable {
    let product: ScannedProduct
    var id: String { product.barcode }
}

/// One search hit: name/brand on the left, lazily fetched kcal + serving on
/// the right.
struct OnlineResultRow: View {
    let result: OpenFoodFactsClient.SearchResult
    let search: OnlineFoodSearch
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .foregroundStyle(.primary)
                    // In Both mode the caption leads with the row's
                    // source ("FDC · Survey (FNDDS)", "OFF · Kirkland").
                    let source = search.showsSourceTags
                        ? (FoodDataCentralClient.fdcId(fromCode: result.barcode) != nil ? "FDC" : "OFF")
                        : nil
                    let caption = [source, result.brand?.isEmpty == false ? result.brand : nil]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if search.fetchingCode == result.barcode {
                    ProgressView()
                } else if let product = search.products[result.barcode] {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.kcal.map {
                            "\($0.formatted(.number.precision(.fractionLength(0)))) kcal"
                        } ?? "no data")
                            .foregroundStyle(product.kcal == nil ? .secondary : .primary)
                            .monospacedDigit()
                        if !product.servingDescription.isEmpty {
                            Text(product.servingDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !search.detailFailures.contains(result.barcode) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(search.fetchingCode != nil)
        .task { search.loadDetail(for: result.barcode) }
    }
}

/// The "Online" list section shared by the Foods screen and the quick-log
/// sheet: a search button until results arrive, then pickable rows.
struct OnlineResultsSection: View {
    /// What the current setting would search — the button's noun.
    static var nextSearchName: String {
        switch SharedStore.textSearchMode {
        case .openFoodFacts: "OpenFoodFacts"
        case .fdc: "FDC"
        case .both: "OpenFoodFacts & FDC"
        }
    }

    let query: String
    let search: OnlineFoodSearch
    let onPick: (ScannedProduct) -> Void
    /// A dead-end search (no matches, or the database was unreachable)
    /// offers manual entry — the new-food form prefilled with the query.
    var onAddManually: ((String) -> Void)?

    var body: some View {
        Section("Online") {
            if search.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(.secondary)
                }
            } else if search.results.isEmpty
                        || query.trimmingCharacters(in: .whitespaces) != search.lastQuery {
                // Also shown when the query changed after a search — the
                // rows below are for the old words, and re-searching must
                // not require emptying the results first.
                Button {
                    Task { await search.search(query) }
                } label: {
                    // Names the source the NEXT search will hit (the
                    // current setting), which can differ from what the
                    // rows below came from — that's the point: the
                    // button re-searches under the new setting.
                    Label(
                        "Search \(Self.nextSearchName) for “\(query.trimmingCharacters(in: .whitespaces))”",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            if let message = search.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // The searched-and-came-up-empty state — no matches or a
            // failed search alike: the label is still a fine food name.
            if let onAddManually,
               !search.isSearching,
               search.results.isEmpty,
               query.trimmingCharacters(in: .whitespaces) == search.lastQuery {
                Button {
                    onAddManually(search.lastQuery)
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
            }
            ForEach(search.results) { result in
                OnlineResultRow(result: result, search: search) {
                    Task { onPick(await search.product(for: result)) }
                }
                .onAppear {
                    // Reaching the last row pulls the next page.
                    if result.id == search.results.last?.id {
                        Task { await search.loadMore() }
                    }
                }
            }
            if search.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(.secondary)
                }
            } else if let more = search.moreMessage {
                Text(more)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Provenance: which database these rows came from, linked
            // to the same search on its own site.
            if !search.results.isEmpty, let provenance = search.provenanceLine {
                Text(.init(provenance))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
