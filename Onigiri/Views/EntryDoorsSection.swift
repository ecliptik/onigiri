import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import OnigiriKit

/// The shared entry doors: ONE row each, identical on Foods, the Log
/// sheet, and the Add Food form. The describe field that briefly lived
/// here moved INTO search as the tap-to-estimate row (AIEstimateSection,
/// PLAN-unified-search) — one field instead of two. The section keeps
/// the scan-door provenance caption slot.
///
/// Three doors now (PLAN-screenshot-nutrition), all feeding the SAME
/// cascade via FoodImageReader: the camera, a pasted image, and a photo
/// pick. The two image doors exist for the eat-out case — the restaurant
/// publishes nutrition on its own site, so the values are only ever in
/// Safari, and retyping them by hand was the whole complaint. Paste is
/// the tidier route: iOS's "Copy and Delete" on a screenshot leaves
/// nothing behind in Photos to clean up later.
struct EntryDoorsSection: View {
    /// Scan-door state owned by the host (barcode lookups etc.).
    var scanBusy = false
    /// Host-provided caption under the scan door (barcode/label/photo
    /// provenance) — nil when there's nothing to say.
    var scanCaption: String?
    let onScan: () -> Void
    /// The image doors deliver the SAME outcomes as the scan sheet, so a
    /// host routes them with the closures it already wrote for ScanSheet.
    /// Both nil (the default) hides the image doors entirely.
    var onLabel: ((ParsedLabel) -> Void)?
    var onFood: ((ScannedProduct) -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var readingStatus = ""
    @State private var failureMessage: String?
    /// Drives the paste door's visibility. `hasImages` is a DETECTION
    /// property — unlike reading the pasteboard it raises no "pasted
    /// from Safari" prompt, so checking it costs the user nothing.
    @State private var clipboardHasImage = false
    @State private var readTask: Task<Void, Never>?

    private var imageDoors: Bool { onLabel != nil || onFood != nil }

    var body: some View {
        Section {
            Button(action: onScan) {
                ScanRowLabel()
            }
            .disabled(scanBusy || isReading)

            if imageDoors {
                if clipboardHasImage {
                    // PasteButton, not a custom row over
                    // UIPasteboard.general.image: a programmatic read
                    // raises the system "would like to paste" alert
                    // EVERY time, and this flow is meant to be repeated.
                    // The tap on this button IS the consent, so no alert
                    // appears. Its chrome is system-drawn and can't be
                    // made to match DoorRowLabel exactly — accepted; the
                    // consent behavior is worth more than the pixel.
                    PasteButton(supportedContentTypes: [.image]) { providers in
                        load(providers)
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .tint(Color.riceToast)
                    .disabled(isReading)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    DoorRowLabel(
                        title: "Choose Photo or Screenshot",
                        systemImage: "photo.on.rectangle")
                }
                .disabled(isReading)
            }

            if scanBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up product…")
                        .foregroundStyle(.secondary)
                }
            }
            if isReading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(readingStatus)
                        .foregroundStyle(.secondary)
                }
            }
            if let failureMessage {
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let scanCaption {
                Text(scanCaption)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            readTask?.cancel()
            readTask = Task {
                defer { photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    failureMessage = "Couldn't load that photo — try another."
                    return
                }
                await read(image)
            }
        }
        // The defining flow is COPY IN SAFARI, THEN SWITCH — the
        // clipboard changes while this app is backgrounded, where
        // changedNotification is unreliable. Re-check on both edges: a
        // flag that can only be set while no observer is listening is
        // the dead-Bool landmine in CLAUDE.md.
        .onAppear { refreshClipboard() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshClipboard() }
        }
        .onDisappear { readTask?.cancel() }
    }

    private func refreshClipboard() {
        guard imageDoors else { return }
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    private func load(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) })
        else {
            failureMessage = "That clipboard item isn't an image."
            return
        }
        readTask?.cancel()
        readTask = Task {
            let image: UIImage? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            guard let image else {
                failureMessage = "Couldn't read that clipboard image — try another."
                return
            }
            await read(image)
        }
    }

    private func read(_ image: UIImage) async {
        isReading = true
        failureMessage = nil
        defer { isReading = false }
        switch await FoodImageReader.read(image, status: { readingStatus = $0 }) {
        case .label(let parsed):
            onLabel?(parsed)
        case .food(let product):
            onFood?(product)
        case .nothing(let message):
            failureMessage = message
        case .cancelled:
            break
        }
    }
}
