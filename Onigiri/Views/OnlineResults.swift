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
    private var detailsInFlight: Set<String> = []
    private var page = 1
    private var hasMore = false
    /// Barcodes whose product carries no calorie data at all — weeded
    /// from results (useless for logging) and kept out of later pages.
    /// A literal 0 kcal stays: that's real data (water, diet soda).
    private var rejected: Set<String> = []

    private static let pageSize = 10
    private let client = OpenFoodFactsClient()
    private(set) var lastQuery = ""

    var hasSearched: Bool { !lastQuery.isEmpty }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        lastQuery = trimmed
        isSearching = true
        message = nil
        moreMessage = nil
        results = []
        page = 1
        hasMore = false
        do {
            let hits = try await client.search(query: trimmed, limit: Self.pageSize)
            guard lastQuery == trimmed else { return } // superseded
            results = hits.filter { !rejected.contains($0.barcode) }
            hasMore = hits.count == Self.pageSize
            if hits.isEmpty {
                message = "No online matches — try different words."
            }
        } catch {
            guard lastQuery == trimmed else { return }
            // Transient failures toast (hosts on each sheet); the inline
            // message stays for result states like "no matches".
            ToastCenter.shared.show(
                error is OpenFoodFactsError
                    ? error.localizedDescription
                    : "Online search failed: \(error.localizedDescription)"
            )
        }
        isSearching = false
    }

    /// The next page, triggered when the last row scrolls into view. A
    /// full page means there may be another; a short/empty page — or a
    /// throttle — ends paging until the next fresh search.
    func loadMore() async {
        guard hasMore, !isSearching, !isLoadingMore, hasSearched else { return }
        let query = lastQuery
        isLoadingMore = true
        do {
            let hits = try await client.search(query: query, limit: Self.pageSize, page: page + 1)
            guard lastQuery == query else { return } // superseded
            page += 1
            hasMore = hits.count == Self.pageSize
            // OFF pages can shift between requests — drop repeats (and
            // anything already weeded for missing calories).
            let known = Set(results.map(\.barcode))
            let fresh = hits.filter { !known.contains($0.barcode) && !rejected.contains($0.barcode) }
            if fresh.isEmpty && !hits.isEmpty { hasMore = false }
            results += fresh
        } catch {
            guard lastQuery == query else { return }
            hasMore = false
            moreMessage = error as? OpenFoodFactsError == .throttled
                ? "OpenFoodFacts is busy — try again in a minute."
                : "Couldn't load more results."
        }
        isLoadingMore = false
    }

    func clear() {
        lastQuery = ""
        results = []
        message = nil
        moreMessage = nil
        isSearching = false
        isLoadingMore = false
        page = 1
        hasMore = false
        rejected = []
    }

    /// Unstructured on purpose: the row's .task would cancel the fetch
    /// when the row scrolls off, then fetch again when it scrolls back.
    /// One in-flight request per barcode, and it runs to completion.
    func loadDetail(for barcode: String) {
        guard products[barcode] == nil, !detailFailures.contains(barcode),
              detailsInFlight.insert(barcode).inserted else { return }
        Task {
            defer { detailsInFlight.remove(barcode) }
            if let product = try? await client.product(barcode: barcode) {
                products[barcode] = product
                // No calorie data at all — weed it, and backfill a page
                // if weeding emptied the list.
                if product.kcal == nil {
                    rejected.insert(barcode)
                    results.removeAll { $0.barcode == barcode }
                    if results.isEmpty, hasMore, !isSearching {
                        await loadMore()
                    }
                }
            } else {
                detailFailures.insert(barcode)
            }
        }
    }

    /// The full product for a picked row — the cached fetch, else a live one,
    /// else the bare search hit (better than nothing).
    func product(for result: OpenFoodFactsClient.SearchResult) async -> ScannedProduct {
        if let cached = products[result.barcode] { return cached }
        fetchingCode = result.barcode
        defer { fetchingCode = nil }
        if let product = try? await client.product(barcode: result.barcode) {
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
                    if let brand = result.brand, !brand.isEmpty {
                        Text(brand)
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
                    Label("Search online for “\(query.trimmingCharacters(in: .whitespaces))”",
                          systemImage: "magnifyingglass")
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
        }
    }
}
