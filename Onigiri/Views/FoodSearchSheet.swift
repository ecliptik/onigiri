import SwiftUI
import OnigiriKit

/// Free-text search of OpenFoodFacts — for foods without barcodes.
/// Picking a result fetches the full product (nutrition included).
struct FoodSearchSheet: View {
    var initialQuery = ""
    let onPick: (ScannedProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = OnlineFoodSearch()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if search.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = search.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(search.results) { result in
                    OnlineResultRow(result: result, search: search) {
                        Task {
                            let product = await search.product(for: result)
                            onPick(product)
                            dismiss()
                        }
                    }
                }
            }
            .compactSections()
            .navigationTitle("Search Database")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "e.g. blueberries")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) {
                Task { await search.search(query) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if !initialQuery.isEmpty {
                    query = initialQuery
                    await search.search(initialQuery)
                }
                // Focus after the sheet's presentation animation settles.
                try? await Task.sleep(for: .milliseconds(350))
                searchFocused = true
            }
        }
    }
}
