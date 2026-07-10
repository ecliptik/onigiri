import SwiftUI
import OnigiriKit

/// Free-text search of OpenFoodFacts — for foods without barcodes.
/// Picking a result fetches the full product (nutrition included).
struct FoodSearchSheet: View {
    var initialQuery = ""
    let onPick: (ScannedProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [OpenFoodFactsClient.SearchResult] = []
    @State private var isSearching = false
    @State private var fetchingCode: String?
    @State private var message: String?
    /// Full products fetched lazily per visible row — the search index has
    /// no nutrition, but calories + serving on the row disambiguate
    /// same-named hits. Also reused when a row is picked.
    @State private var products: [String: ScannedProduct] = [:]
    @State private var detailFailures: Set<String> = []
    @FocusState private var searchFocused: Bool

    private let client = OpenFoodFactsClient()

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        pick(result)
                    } label: {
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
                            if fetchingCode == result.barcode {
                                ProgressView()
                            } else if let product = products[result.barcode] {
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
                            } else if !detailFailures.contains(result.barcode) {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(fetchingCode != nil)
                    .task { await loadDetail(for: result.barcode) }
                }
            }
            .navigationTitle("Search Database")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "e.g. blueberries")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if !initialQuery.isEmpty {
                    query = initialQuery
                    await search()
                }
                // Focus after the sheet's presentation animation settles.
                try? await Task.sleep(for: .milliseconds(350))
                searchFocused = true
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        message = nil
        results = []
        do {
            results = try await client.search(query: trimmed)
            if results.isEmpty {
                message = "No matches — try different words, or enter it manually."
            }
        } catch {
            message = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }

    private func loadDetail(for barcode: String) async {
        guard products[barcode] == nil, !detailFailures.contains(barcode) else { return }
        if let product = try? await client.product(barcode: barcode) {
            products[barcode] = product
        } else {
            detailFailures.insert(barcode)
        }
    }

    private func pick(_ result: OpenFoodFactsClient.SearchResult) {
        if let cached = products[result.barcode] {
            onPick(cached)
            dismiss()
            return
        }
        fetchingCode = result.barcode
        Task {
            defer { fetchingCode = nil }
            do {
                let product = try await client.product(barcode: result.barcode)
                onPick(product)
                dismiss()
            } catch {
                // Fall back to what the search hit had — better than nothing.
                onPick(ScannedProduct(
                    barcode: result.barcode,
                    name: result.brand.map { "\(result.name) (\($0))" } ?? result.name,
                    kcal: nil,
                    sodiumMg: nil,
                    servingDescription: "",
                    nutrients: NutrientValues()
                ))
                dismiss()
            }
        }
    }
}
