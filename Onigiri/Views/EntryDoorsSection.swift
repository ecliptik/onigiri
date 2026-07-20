import SwiftUI
import OnigiriKit

/// The shared scan door: ONE row (ScanRowLabel), one camera, identical
/// on Foods, the Log sheet, and the Add Food form. The describe field
/// that briefly lived here moved INTO search as the tap-to-estimate
/// row (AIEstimateSection, PLAN-unified-search) — one field instead of
/// two. The section keeps the scan-door provenance caption slot.
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
