import SwiftUI
import OnigiriKit

/// Pushed from a tracked-metric slot in Settings: every nutrient a slot
/// can track, grouped and searchable, with its label unit alongside.
struct NutrientPickerView: View {
    @Binding var selectionKey: String
    /// The OTHER slot's nutrient key — selecting it here would put the
    /// same metric on Today twice, with two Settings sections editing
    /// one target. Disabled with a hint instead.
    var takenKey: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            // "None" switches the slot off — Today and the calendar day
            // card simply drop it.
            if searchText.isEmpty {
                Section {
                    Button {
                        selectionKey = SharedStore.trackedMetricNone
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectionKey == SharedStore.trackedMetricNone {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
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
                    let taken = nutrient.key == takenKey
                    Button {
                        selectionKey = nutrient.key
                        dismiss()
                    } label: {
                        HStack {
                            Text(nutrient.displayName)
                                .foregroundStyle(taken ? .secondary : .primary)
                            Spacer()
                            if taken {
                                Text("other slot")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(.secondary)
                            if nutrient.key == selectionKey {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(taken)
                }
            }
        }
    }
}
