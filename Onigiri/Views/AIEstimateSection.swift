import SwiftUI
import OnigiriKit

/// The tap-to-estimate row that leads every search-result list
/// (PLAN-unified-search): "✨ Estimate '<query>'" — one tap, ONE
/// inference (never per keystroke: remote providers spend the user's
/// own tokens, and the on-device model takes seconds). The result
/// becomes a pickable row carrying the provider-named caption; picking
/// hands the host a ScannedProduct — the same currency as an online
/// pick, so every host routes it with paths it already has (portion
/// sheet on the Log sheet, prefilled form on Foods, apply() on the
/// form). Editing the query resets to the idle row.
struct AIEstimateSection: View {
    let query: String
    let onPick: (ScannedProduct) -> Void

    private enum Phase {
        case idle
        case estimating
        case result(FoodIntelligence.DescribedFood)
        case failed
    }

    @State private var phase = Phase.idle
    /// The query the current phase belongs to — a changed query
    /// invalidates a stale estimate back to the idle row.
    @State private var phaseQuery = ""
    /// The in-flight inference, stored so an edited query or a vanished
    /// section CANCELS it: an orphaned completion repainted a stale
    /// result over the reset row, and for BYO-AI providers the request
    /// keeps spending the user's tokens after they've moved on
    /// (2026-07-20 audit).
    @State private var estimateTask: Task<Void, Never>?

    @AppStorage(AIProviderSettings.enabledKey, store: SharedStore.defaults) private var aiEnabled = false
    @AppStorage(AIProviderSettings.hintDismissedKey, store: SharedStore.defaults) private var hintDismissed = false

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // AI is off by default — a one-time, dismissable pointer at the
        // switch keeps the feature discoverable without being an AI
        // affordance itself (tap the x and it never returns).
        if !aiEnabled, !hintDismissed, !trimmed.isEmpty {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.riceToast)
                    Text("AI estimates are available — turn them on in Settings → AI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        hintDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            // HIG 44 pt tap target via hit area only —
                            // the negative inset must not move layout.
                            .contentShape(Rectangle().inset(by: -14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss AI hint")
                }
            }
        }
        if FoodIntelligence.isAvailable, !trimmed.isEmpty {
            Section {
                switch phase {
                case .idle:
                    Button {
                        estimate(trimmed)
                    } label: {
                        // The provider NAME is the AI signal (the user:
                        // a bare "Estimate" + sparkle didn't read as AI)
                        // — and for remote providers it's also the
                        // disclosure of where the typed text will go.
                        // No quoted-query subtitle: the query is already
                        // visible in the search field (the user, 2026-07-20).
                        Label {
                            Text("Estimate with \(AIProviderSettings.selected.displayName)")
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.riceToast)
                        }
                    }
                case .estimating:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Estimating…")
                            .foregroundStyle(.secondary)
                    }
                case .result(let food):
                    Button {
                        onPick(product(from: food))
                    } label: {
                        resultRow(food)
                    }
                    .buttonStyle(.plain)
                case .failed:
                    Button {
                        estimate(trimmed)
                    } label: {
                        Label("Couldn't estimate — tap to try again", systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onChange(of: query) { _, updated in
                if updated.trimmingCharacters(in: .whitespaces) != phaseQuery {
                    estimateTask?.cancel()
                    phase = .idle
                }
            }
            .onDisappear { estimateTask?.cancel() }
        }
    }

    /// Name + provider caption, kcal/sodium trailing — the online-row
    /// grammar, with the provenance where the brand line would sit.
    private func resultRow(_ food: FoodIntelligence.DescribedFood) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .foregroundStyle(.primary)
                Text(AIProviderSettings.selected.estimateCaption)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(food.kcal, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
                Text(TrackedNutrient.sodium.captionText(food.sodiumMg, sodium: SharedStore.sodiumUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
    }

    private func product(from food: FoodIntelligence.DescribedFood) -> ScannedProduct {
        ScannedProduct(
            barcode: "",
            name: food.name,
            kcal: food.kcal,
            sodiumMg: food.sodiumMg,
            servingDescription: food.serving,
            nutrients: food.nutrients,
            aiGenerated: true)
    }

    private func estimate(_ trimmed: String) {
        phaseQuery = trimmed
        phase = .estimating
        estimateTask?.cancel()
        estimateTask = Task {
            let food = await FoodIntelligence.describeFood(trimmed)
            // A cancelled or superseded completion must not repaint the
            // row — the query it answered is no longer on screen.
            guard !Task.isCancelled, trimmed == phaseQuery else { return }
            if let food {
                phase = .result(food)
            } else {
                phase = .failed
            }
        }
    }
}
