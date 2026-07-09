import SwiftUI
import OnigiriKit

/// Free-text search of OpenFoodFacts — for foods without barcodes.
struct FoodSearchSheet: View {
    var initialQuery = ""
    let onPick: (ScannedProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ScannedProduct] = []
    @State private var isSearching = false
    @State private var message: String?

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
                ForEach(Array(results.enumerated()), id: \.offset) { _, product in
                    Button {
                        onPick(product)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if let kcal = product.kcal {
                                    Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal")
                                }
                                Text(product.servingDescription)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search Database")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "e.g. blueberries")
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
}
