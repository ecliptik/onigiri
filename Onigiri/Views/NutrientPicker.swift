import SwiftUI
import OnigiriKit

/// Pushed from a tracked-metric slot in Settings: every nutrient a slot
/// can track, grouped and searchable, with its label unit alongside.
struct NutrientPickerView: View {
    @Binding var selectionKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            group("General", TrackedNutrient.general)
            group("Macronutrients", TrackedNutrient.macros)
            group("Minerals", Micronutrient.minerals.map(TrackedNutrient.micro))
            group("Vitamins", Micronutrient.vitamins.map(TrackedNutrient.micro))
        }
        .compactSections()
        .readableContentWidth()
        .navigationTitle("Tracked Metric")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search nutrients")
    }

    @ViewBuilder
    private func group(_ title: String, _ nutrients: [TrackedNutrient]) -> some View {
        let visible = nutrients.filter {
            searchText.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
        if !visible.isEmpty {
            Section(title) {
                ForEach(visible) { nutrient in
                    Button {
                        selectionKey = nutrient.key
                        dismiss()
                    } label: {
                        HStack {
                            Text(nutrient.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(.secondary)
                            if nutrient.key == selectionKey {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}
