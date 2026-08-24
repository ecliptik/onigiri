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
