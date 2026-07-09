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
                            }
                        }
                    }
                    .disabled(fetchingCode != nil)
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

    private func pick(_ result: OpenFoodFactsClient.SearchResult) {
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
