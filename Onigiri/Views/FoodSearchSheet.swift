import SwiftUI
import OnigiriKit

/// Free-text search of OpenFoodFacts — for foods without barcodes.
/// Picking a result fetches the full product (nutrition included).
/// Renders the SAME OnlineResultsSection as Foods and the Log sheet —
/// this used to be a hand-rolled third list that kept drifting (stale
/// results, no failure state, no Add Food fallback).
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
                // Anchor the empty sheet: with the search bar at the
                // bottom (the app-wide standard), a completely blank
                // list above it would read upside down.
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Search OpenFoodFacts")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    OnlineResultsSection(query: query, search: search, onPick: { product in
                        onPick(product)
                        dismiss()
                    }, onAddManually: { name in
                        // Hand the searched name back to the form as a
                        // name-only product.
                        onPick(ScannedProduct(
                            barcode: "", name: name, kcal: nil, sodiumMg: nil,
                            servingDescription: "", nutrients: NutrientValues()
                        ))
                        dismiss()
                    })
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
            .onChange(of: query) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    search.clear()
                }
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
