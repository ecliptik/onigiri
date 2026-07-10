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
    private(set) var message: String?
    private(set) var products: [String: ScannedProduct] = [:]
    private(set) var detailFailures: Set<String> = []
    private(set) var fetchingCode: String?

    private let client = OpenFoodFactsClient()
    private var lastQuery = ""

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
        results = []
        do {
            let hits = try await client.search(query: trimmed)
            guard lastQuery == trimmed else { return } // superseded
            results = hits
            if hits.isEmpty {
                message = "No online matches — try different words."
            }
        } catch {
            guard lastQuery == trimmed else { return }
            message = "Online search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }

    func clear() {
        lastQuery = ""
        results = []
        message = nil
        isSearching = false
    }

    func loadDetail(for barcode: String) async {
        guard products[barcode] == nil, !detailFailures.contains(barcode) else { return }
        if let product = try? await client.product(barcode: barcode) {
            products[barcode] = product
        } else {
            detailFailures.insert(barcode)
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
        .task { await search.loadDetail(for: result.barcode) }
    }
}

/// The "Online" list section shared by the Foods screen and the quick-log
/// sheet: a search button until results arrive, then pickable rows.
struct OnlineResultsSection: View {
    let query: String
    let search: OnlineFoodSearch
    let onPick: (ScannedProduct) -> Void

    var body: some View {
        Section("Online") {
            if search.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(.secondary)
                }
            } else if search.results.isEmpty {
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
            ForEach(search.results) { result in
                OnlineResultRow(result: result, search: search) {
                    Task { onPick(await search.product(for: result)) }
                }
            }
        }
    }
}
