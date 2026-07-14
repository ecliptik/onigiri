import SwiftUI
import OnigiriKit

/// The watch's view of today's log (page between Metrics and Favorites):
/// every food entry, tap to adjust its calories or remove it — the
/// quick fixes for a fat-fingered watch log, without reaching for the
/// phone. Water stays phone-side; the log here is food only.
struct WatchLogView: View {
    let model: WatchModel
    @State private var editing: FoodLogEntry?

    var body: some View {
        NavigationStack {
            List {
                if model.foodLog.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let flash = model.flash {
                    Text(flash)
                        .font(.footnote)
                        .foregroundStyle(model.flashIsError ? .orange : .green)
                }
                ForEach(model.foodLog) { entry in
                    if entry.editable {
                        Button {
                            editing = entry
                        } label: {
                            entryLabel(entry)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.deleteEntry(entry) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    } else {
                        // Another app's entry (reads span all sources by
                        // design): counted, but HealthKit refuses our
                        // deletes — no edit/remove that can only error.
                        entryLabel(entry)
                            .accessibilityHint("Logged by another app")
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { entry in
                WatchEntryEditSheet(model: model, entry: entry)
            }
        }
        .onAppear {
            // Page swipes re-fire this (and TabView pre-renders
            // neighbors) — the model skips when fresh.
            Task { await model.refreshIfStale() }
        }
    }

    private func entryLabel(_ entry: FoodLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .lineLimit(1)
            HStack {
                Text(entry.date, style: .time)
                Spacer()
                Text("\(entry.kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// Adjust an entry's calories (crown or ±25 taps) or remove it. Saving
/// rescales sodium and the extended nutrients with the kcal.
private struct WatchEntryEditSheet: View {
    let model: WatchModel
    let entry: FoodLogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var kcal: Double

    init(model: WatchModel, entry: FoodLogEntry) {
        self.model = model
        self.entry = entry
        _kcal = State(initialValue: entry.kcal.rounded())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    adjustButton("minus", by: -25)
                    VStack(spacing: 0) {
                        Text("\(kcal, format: .number.precision(.fractionLength(0)))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .focusable()
                    .digitalCrownRotation(
                        $kcal, from: 0, through: 5000, by: 5,
                        sensitivity: .medium
                    )
                    adjustButton("plus", by: 25)
                }

                Button {
                    Task {
                        if await model.editEntry(entry, kcal: kcal.rounded()) {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.ricePaper)
                .foregroundStyle(Color.onRicePaper)
                .disabled(kcal.rounded() == entry.kcal.rounded())

                Button(role: .destructive) {
                    Task {
                        if await model.deleteEntry(entry) {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Remove")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 4)
        }
    }

    private func adjustButton(_ symbol: String, by delta: Double) -> some View {
        Button {
            kcal = min(5000, max(0, kcal + delta))
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
        }
        .buttonStyle(.bordered)
        .clipShape(.circle)
    }
}

#Preview {
    WatchLogView(model: WatchModel())
}
