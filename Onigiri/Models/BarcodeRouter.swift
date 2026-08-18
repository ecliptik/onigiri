import Foundation
import OnigiriKit

/// The one known-barcode → portion-sheet / unknown-barcode → prefilled-form
/// route, shared by the Foods screen and the Log sheet (each had its own
/// copy until 2.1). The caller supplies how to find a saved item for the
/// code — including any recency bump — and how to present each
/// destination; this owns the branch, the OpenFoodFacts fetch, the
/// in-flight flag, and the error toast.
@MainActor
enum BarcodeRouter {
    /// A barcode the database doesn't have is not a failure, it's the
    /// next step: the nutrition panel is physically in the user's hand.
    /// Saying "that barcode isn't in OpenFoodFacts" and stopping put the
    /// work back on them at the exact moment the camera was already open
    /// and already able to read the label.
    static let missNotice = "Not in the database — scan the nutrition label instead."

    static func lookUp(
        _ code: String,
        savedTarget: (String) -> PortionTarget?,
        /// A plain callback, not a `Binding` — the one SwiftUI type this
        /// route carried, and the reason its branch logic couldn't be
        /// unit-tested without constructing one (audit, 2026-08-17).
        /// Callers pass `{ isLookingUp = $0 }`.
        setLookingUp: @escaping (Bool) -> Void,
        presentPortion: @escaping (PortionTarget) -> Void,
        presentForm: @escaping (ProductPrefill) -> Void,
        /// Reopen the scanner on the label path. Only for `.notFound` —
        /// a throttled or offline lookup might well succeed on a retry,
        /// and sending someone to photograph a label instead would be
        /// worse advice than saying "try again in a minute".
        presentLabelScan: (() -> Void)? = nil
    ) {
        if let target = savedTarget(code) {
            // One-turn deferral, the label handoff's pattern: the
            // scanner sheet dismisses itself right after delivering the
            // code, and a same-turn item swap is torn down with it —
            // the library hit ran synchronously and the portion sheet
            // died with the scanner, a silent no-op scan (2026-07-22).
            // The fetch path below gets this deferral for free from
            // network latency.
            Task { presentPortion(target) }
            return
        }
        setLookingUp(true)
        Task {
            defer { setLookingUp(false) }
            do {
                let product = try await OpenFoodFactsClient().product(barcode: code)
                presentForm(ProductPrefill(product: product))
            } catch OpenFoodFactsError.notFound where presentLabelScan != nil {
                // Straight back to the camera, on the label path. One
                // turn later: the scanner that delivered this code is
                // still dismissing, and re-presenting into that same
                // slot mid-dismissal is the swap that dies silently
                // (the 2026-07-22 landmine, above).
                presentLabelScan?()
            } catch {
                // Transient failures toast, like everything else.
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }
}
