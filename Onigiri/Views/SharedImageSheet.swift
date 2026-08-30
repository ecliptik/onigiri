import SwiftUI
import UIKit
import OnigiriKit

/// A photo shared into Onigiri from anywhere — Photos, Safari, Messages
/// (`plans/PLAN-menu-import.md`).
///
/// It runs `FoodImageReader` with `.imported`, which is EXACTLY what the
/// paste door runs. That is the whole design: a shared screenshot must
/// read the way a pasted one does, because they are the same picture
/// arriving by a different route. Nothing is forked — label parse, AI
/// blank-fill, the screenshot name read, the sign read and the photo
/// identify all come along unchanged.
///
/// A read that lists SEVERAL foods hands its rows to `MenuPickerFlow`
/// and stays there until Done: the sheet used to tear itself down with
/// the first form it opened, so a screenshot of a menu section had to be
/// re-shared and re-read for the second item
/// (`plans/PLAN-multi-item-import.md`).
struct SharedImageSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var phase = Phase.reading
    @State private var status = "Reading the photo…"
    /// The rows a multi-item read produced, whether they came from a
    /// photographed menu or from a screenshot listing several foods —
    /// one list, one chooser.
    @State private var menuItems: [MenuRow] = []
    @State private var menuSource: String?
    @State private var pick: Pick?
    /// An ESTIMATE waiting to be checked — see `EstimateRefineStep`.
    @State private var estimate: Estimate?

    private enum Phase: Equatable {
        case reading
        case failed(String)
        /// The form is up; this sheet is just its host now.
        case handedOff
        /// A list to order from; `MenuPickerFlow` owns the screen.
        case choosing
        /// One estimate, with a field to correct it before it fills the
        /// form (`plans/PLAN-refine-with-context.md`).
        case checking
    }

    private struct Estimate: Identifiable {
        let id = UUID()
        let context: RefineContext
    }

    private struct Pick: Identifiable {
        let id = UUID()
        let product: ScannedProduct
    }

    var body: some View {
        NavigationStack {
            content
        }
        .task { await read() }
        // A SINGLE food still goes to the full form, which can edit the
        // numbers — one item costs one trip, and these reads are the
        // ones worth editing. The deferred assignment stays: this used to
        // swap one sheet's binding while another was dismissing, which
        // is the 2026-07-22 race, and it left the picker on a blank
        // hand-off screen (audit, 2026-08-17). Nothing swaps now — the
        // list lives in this view's own body — but the form is still
        // raised from a closure the reader finishes in.
        .sheet(item: $pick, onDismiss: { dismiss() }) { pick in
            FoodFormView(food: nil, prefill: pick.product)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .reading:
            ContentUnavailableView {
                Label(status, systemImage: "text.viewfinder")
            } description: {
                ProgressView()
            }
            .modifier(HostChrome(dismiss: dismiss))
        case .failed(let message):
            ContentUnavailableView {
                Label("No nutrition found", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text(message)
            }
            .modifier(HostChrome(dismiss: dismiss))
        case .handedOff:
            // Briefly visible behind the form; never a dead end, because
            // dismissing the form dismisses this too.
            Color.clear
        case .choosing:
            MenuPickerFlow(
                rows: menuItems,
                suggestedSource: menuSource,
                completion: .logging(saving: .optional, write: log, saveOnly: saveOnly),
                onFinish: { _ in dismiss() })
        case .checking:
            if let estimate {
                // Cancel, not Back: there is no camera behind a shared
                // photo to go back TO.
                EstimateRefineStep(
                    context: estimate.context,
                    backTitle: "Cancel",
                    onBack: { dismiss() },
                    onUse: { product in
                        pick = Pick(product: product)
                        phase = .handedOff
                    })
            }
        }
    }

    /// Title and way out for the phases this view still owns. Once
    /// `MenuPickerFlow` is up it contributes its own — and adds Done
    /// beside Cancel as soon as something has been logged.
    private struct HostChrome: ViewModifier {
        let dismiss: DismissAction

        func body(content: Content) -> some View {
            content
                .navigationTitle("Add from Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
    }

    private func log(_ request: MenuLogRequest) async -> String? {
        let ok = await LogActions.logFood(
            name: request.name,
            kcal: (request.label.kcal ?? 0) * request.quantity,
            sodiumMg: (request.label.sodiumMg ?? 0) * request.quantity,
            nutrients: request.label.nutrients.scaled(by: request.quantity),
            category: request.category,
            aiGenerated: request.label.aiGenerated,
            quantity: request.quantity)
        guard ok else { return "Couldn't log that item. Try again." }
        if request.saveToLibrary { MenuLibrarySave.insert(request, into: context) }
        return nil
    }

    /// The library keeps the dish; nothing goes to Health.
    private func saveOnly(_ request: MenuLogRequest) async -> String? {
        MenuLibrarySave.insert(request, into: context)
        return nil
    }

    private func read() async {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            phase = .failed("Onigiri couldn't open that image.")
            return
        }
        switch await FoodImageReader.read(image, source: .imported, status: { status = $0 }) {
        case .label(let parsed):
            phase = .handedOff
            pick = Pick(product: parsed.scannedProduct())
        case .food(let product, let refine):
            if let refine {
                estimate = Estimate(context: refine)
                phase = .checking
            } else {
                phase = .handedOff
                pick = Pick(product: product)
            }
        case .candidates(let list):
            // A screenshot listing several foods — the same list a menu
            // gets, because it is the same question and a dialog could
            // neither report what had been logged nor be returned to.
            menuItems = MenuRow.list(from: list)
            phase = .choosing
        case .menu(let items, let source):
            // A photographed MENU shared in — the same list, for the
            // same reason: a board lists dozens.
            menuSource = source
            menuItems = items
            phase = .choosing
        case .nothing(let message):
            phase = .failed(message)
        case .cancelled:
            dismiss()
        }
    }
}
