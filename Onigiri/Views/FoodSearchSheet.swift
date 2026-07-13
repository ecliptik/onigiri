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
                // Anchor the empty sheet: with the search bar at the
                // bottom (the app-wide standard), a completely blank
                // list above it would read upside down.
                if !search.hasSearched && !search.isSearching && search.results.isEmpty {
                    Text("Search OpenFoodFacts for foods without barcodes — results appear here.")
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
                    .onAppear {
                        // Same paging as the Foods/Log search sections:
                        // the last row pulls the next page.
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
            .compactSections()
            .navigationTitle("Search Database")
            .navigationBarTitleDisplayMode(.inline)
            // Bottom placement like every other search in the app (the
            // iOS 26 standard) — Micheal wants one search UX everywhere.
            // The empty-sheet hint row above keeps the blank state from
            // reading upside down (the reason this was once top-pinned).
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
        .toastHost()
    }
}
