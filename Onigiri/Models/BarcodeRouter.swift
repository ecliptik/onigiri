import SwiftUI
import OnigiriKit

/// The one known-barcode → portion-sheet / unknown-barcode → prefilled-form
/// route, shared by the Foods screen and the Log sheet (each had its own
/// copy until 2.1). The caller supplies how to find a saved item for the
/// code — including any recency bump — and how to present each
/// destination; this owns the branch, the OpenFoodFacts fetch, the
/// in-flight flag, and the error toast.
@MainActor
enum BarcodeRouter {
    static func lookUp(
        _ code: String,
        savedTarget: (String) -> PortionTarget?,
        isLookingUp: Binding<Bool>,
        presentPortion: (PortionTarget) -> Void,
        presentForm: @escaping (ProductPrefill) -> Void
    ) {
        if let target = savedTarget(code) {
            presentPortion(target)
            return
        }
        isLookingUp.wrappedValue = true
        Task {
            defer { isLookingUp.wrappedValue = false }
            do {
                let product = try await OpenFoodFactsClient().product(barcode: code)
                presentForm(ProductPrefill(product: product))
            } catch {
                // Transient failures toast, like everything else.
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }
}
