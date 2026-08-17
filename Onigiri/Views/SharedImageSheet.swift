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
/// blank-fill, the screenshot name read, the sign read, the photo
/// identify, and the "Which item?" dialog all come along unchanged.
struct SharedImageSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.reading
    @State private var status = "Reading the photo…"
    @State private var candidates: [ParsedLabel] = []
    @State private var menuItems: [MenuRow] = []
    @State private var menuSource: String?
    @State private var pick: Pick?

    private enum Phase: Equatable {
        case reading
        case failed(String)
        /// The form is up; this sheet is just its host now.
        case handedOff
    }

    private struct Pick: Identifiable {
        let id = UUID()
        let product: ScannedProduct
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add from Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await read() }
        // The same chooser the paste door and the scan sheet raise, so a
        // multi-item photo behaves identically wherever it arrived from.
        .screenshotCandidates($candidates) { picked in
            pick = Pick(product: picked.scannedProduct())
        }
        .menuPhotoPicker($menuItems, suggestedSource: menuSource) { picked in
            pick = Pick(product: picked.scannedProduct())
        }
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
        case .failed(let message):
            ContentUnavailableView {
                Label("No nutrition found", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text(message)
            }
        case .handedOff:
            // Briefly visible behind the form; never a dead end, because
            // dismissing the form dismisses this too.
            Color.clear
        }
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
        case .food(let product):
            phase = .handedOff
            pick = Pick(product: product)
        case .candidates(let list):
            phase = .handedOff
            candidates = list
        case .menu(let items, let source):
            // A photographed MENU shared in — the same picker the scan
            // door raises, for the same reason: a board lists dozens.
            phase = .handedOff
            menuSource = source
            menuItems = items
        case .nothing(let message):
            phase = .failed(message)
        case .cancelled:
            dismiss()
        }
    }
}
