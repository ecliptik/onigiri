import SwiftUI
import OnigiriKit

/// The shared entry doors (PLAN-entry-doors): ONE scan row and ONE
/// "Describe food" field, rendered identically on Foods, the Log
/// sheet, and the Add Food form. The section owns the copy, the
/// progress rows, and the describe door's provenance caption (always
/// under the door that produced the estimate — the old form showed it
/// under the SCAN row plus a static footer, twice). Hosts wire the
/// actions: what scanning opens and where a finished estimate goes.
struct EntryDoorsSection: View {
    /// Scan-door state owned by the host (barcode lookups etc.).
    var scanBusy = false
    /// Host-provided caption under the SCAN door (barcode/label/photo
    /// provenance) — nil when there's nothing to say.
    var scanCaption: String?
    let onScan: () -> Void
    /// A finished estimate, already validated — the host routes it
    /// (form prefill on Foods/Add Food, portion sheet on the Log
    /// sheet). Only called on success; failures caption the door.
    let onEstimate: (FoodIntelligence.DescribedFood) -> Void

    @State private var describeText = ""
    @State private var isEstimating = false
    @State private var describeCaption: String?

    var body: some View {
        Section {
            Button(action: onScan) {
                ScanRowLabel()
            }
            .disabled(scanBusy)
            if scanBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up product…")
                        .foregroundStyle(.secondary)
                }
            }
            if let scanCaption {
                Text(scanCaption)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        // The describe door follows the same availability gate as every
        // AI affordance — with BYO-AI that means "the SELECTED provider
        // is usable", on-device or not.
        if FoodIntelligence.isAvailable {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.riceToast)
                    TextField(
                        "Describe food — half cup rice, fried egg",
                        text: $describeText
                    )
                    .onSubmit { estimate() }
                    .submitLabel(.done)
                }
                if isEstimating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Estimating…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let describeCaption {
                    Text(describeCaption)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func estimate() {
        let description = describeText.trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty, !isEstimating else { return }
        isEstimating = true
        describeCaption = nil
        Task {
            defer { isEstimating = false }
            guard let estimate = await FoodIntelligence.describeFood(description) else {
                describeCaption = "Couldn't estimate that — try more detail, or add it by hand."
                return
            }
            describeText = ""
            describeCaption = AIProviderSettings.selected.estimateCaption
            onEstimate(estimate)
        }
    }
}
