import SwiftUI
import OnigiriKit

/// The shared entry door: ONE scan row, identical on Foods, the Log
/// sheet, and the Add Food form. The describe field that briefly lived
/// here moved INTO search as the tap-to-estimate row (AIEstimateSection,
/// PLAN-unified-search) — one field instead of two. The section keeps
/// the scan-door provenance caption slot.
///
/// A PASTE door lived here too (PLAN-screenshot-nutrition) and was
/// REMOVED (the user, 2026-08-17): the share sheet covers the
/// copy-it-in-Safari case end to end now — share the screenshot or the
/// page straight into Onigiri — so the clipboard-gated row was a second
/// door to the same `FoodImageReader` cascade, with a system paste
/// prompt on top. Same fate as the picked-from-library door before it
/// (the user, 2026-07-24): the scan sheet's photos button already
/// covers saved images.
struct EntryDoorsSection: View {
    /// Scan-door state owned by the host (barcode lookups etc.).
    var scanBusy = false
    /// Host-provided caption under the scan door (barcode/label/photo
    /// provenance) — nil when there's nothing to say.
    var scanCaption: String?
    let onScan: () -> Void

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
    }
}

/// The "which item?" chooser for a screenshot that listed several
/// foods (PLAN-screenshot-nutrition Part C). A confirmationDialog, not
/// a sheet, on purpose: the image routes (the scan sheet's photo path
/// and the shared-image sheet) both raise it, and swapping a sheet from
/// inside a sheet is the dismissal race that bit twice on 2026-07-22.
extension View {
    func screenshotCandidates(
        _ candidates: Binding<[ParsedLabel]>,
        onPick: @escaping (ParsedLabel) -> Void
    ) -> some View {
        confirmationDialog(
            "Which item?",
            isPresented: Binding(
                get: { !candidates.wrappedValue.isEmpty },
                set: { if !$0 { candidates.wrappedValue = [] } }),
            titleVisibility: .visible
        ) {
            ForEach(Array(candidates.wrappedValue.enumerated()), id: \.offset) { _, candidate in
                Button(candidate.candidateLabel) {
                    candidates.wrappedValue = []
                    onPick(candidate)
                }
            }
            Button("Cancel", role: .cancel) { candidates.wrappedValue = [] }
        } message: {
            Text("That screenshot listed more than one food.")
        }
    }
}

extension ParsedLabel {
    /// One dialog row: the dish and what logging it would cost. Falls
    /// back to the serving when the read produced no name, so a row is
    /// never blank.
    var candidateLabel: String {
        let title = name ?? servingDescription ?? "Unnamed item"
        guard let kcal else { return title }
        return "\(title) — \(kcal.formatted(.number.precision(.fractionLength(0)))) kcal"
    }
}
