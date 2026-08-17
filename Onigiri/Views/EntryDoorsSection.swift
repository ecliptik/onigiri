import SwiftUI
import OnigiriKit

/// The shared entry doors: ONE row each, identical on Foods, the Log
/// sheet, and the Add Food form. The describe field that briefly lived
/// here moved INTO search as the tap-to-estimate row (AIEstimateSection,
/// PLAN-unified-search) — one field instead of two. The section keeps
/// the scan-door provenance caption slot.
///
/// Two doors (PLAN-screenshot-nutrition), both feeding the SAME cascade
/// via FoodImageReader: the camera, and a pasted image. The paste door
/// exists for the eat-out case — the restaurant publishes nutrition on
/// its own site, so the values are only ever in Safari, and retyping
/// them by hand was the whole complaint. iOS's "Copy and Delete" on a
/// screenshot leaves nothing behind in Photos to clean up either.
///
/// A picked-from-library door lived here briefly and was REMOVED (the
/// user, 2026-07-24): the scan sheet's own photos button already covers
/// saved images, and a second row for it was noise.
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
    @State private var isReading = false
    @State private var readingStatus = ""
    @State private var failureMessage: String?
    /// Drives the paste door's visibility. `hasImages` is a DETECTION
    /// property — unlike reading the pasteboard it raises no "pasted
    /// from Safari" prompt, so checking it costs the user nothing.
    @State private var clipboardHasImage = false
    @State private var readTask: Task<Void, Never>?
    /// Non-empty while the "which item?" dialog is up.
    @State private var candidates: [ParsedLabel] = []
    /// Non-empty while the photographed-menu picker is up.
    @State private var menuItems: [MenuRow] = []
    @State private var menuSource: String?

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
                    // UNDER EVALUATION (2026-07-24): a plain door row
                    // that reads the pasteboard itself, instead of the
                    // system PasteButton this replaced. Two differences,
                    // both deliberate — the row can say what it does
                    // ("Paste Nutrition Screenshot", matching the scan
                    // door), and iOS raises its "would like to paste"
                    // confirmation, which the user wants VISIBLE rather
                    // than implied by a tap.
                    //
                    // Privacy is unchanged either way: the app can never
                    // read the clipboard un-prompted, and the row's
                    // visibility still comes from hasImages, which
                    // reports only THAT an image exists, never what it
                    // is, and raises nothing.
                    //
                    // Open question this variant exists to answer: how
                    // often the alert actually fires. If iOS remembers
                    // the grant per source/session it's a clear win; if
                    // it asks on every paste, reverting to PasteButton
                    // is one commit.
                    Button {
                        load(UIPasteboard.general.itemProviders)
                    } label: {
                        DoorRowLabel(
                            title: "Paste Nutrition Screenshot",
                            systemImage: "doc.on.clipboard")
                    }
                    .disabled(isReading)
                }
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
        // The defining flow is COPY IN SAFARI, THEN SWITCH — the
        // clipboard changes while this app is backgrounded, where
        // changedNotification is unreliable. Re-check on both edges: a
        // flag that can only be set while no observer is listening is
        // the dead-Bool landmine in CLAUDE.md.
        .onAppear { refreshClipboard() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshClipboard()
            } else if phase == .background {
                // Suspension is the one unambiguous "stop" this section
                // gets: a cascade mid-flight when the app suspends either
                // burns background time or dies unrecoverably (ScanSheet's
                // rule). `.background` specifically, not any non-active
                // phase — an `.inactive` blip from a system overlay is
                // not the user walking away.
                readTask?.cancel()
            }
        }
        // NO `.onDisappear { readTask?.cancel() }`, and that absence is
        // the fix (audit, 2026-08-17). This section is inside a
        // `.searchable` container at every call site — the food form and
        // the Log sheet — and CLAUDE.md records that such sections get a
        // TRANSIENT onDisappear/onAppear pair when the keyboard
        // dismisses. Tapping the paste row is itself what dismisses that
        // keyboard, so the cancel landed on the very read the tap had
        // just started: `FoodImageReader` honours `Task.isCancelled`, so
        // the read really died, and `case .cancelled: break` meant it
        // died in silence, indistinguishable from nothing happening.
        //
        // `EstimateRow`'s cancel-then-resume-on-reappear can't rescue
        // this one: the image came from an item provider that has
        // already been consumed, so there is nothing left to restart
        // from. Letting an abandoned read finish costs one bounded OCR
        // pass whose results land in discarded @State.
        .screenshotCandidates($candidates) { picked in
            onLabel?(picked)
        }
        .menuPhotoPicker($menuItems, suggestedSource: menuSource) { picked in
            onLabel?(picked)
        }
    }

    private func refreshClipboard() {
        guard imageDoors else { return }
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    private func load(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) })
        else {
            // Also the "Don't Allow" path: iOS simply hands back
            // nothing, so declined and empty are indistinguishable here.
            failureMessage = "Nothing readable on the clipboard."
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
        // .imported: these doors are where SCREENSHOTS arrive, so the
        // reader also does the screenshot read that supplies a name.
        switch await FoodImageReader.read(
            image, source: .imported, status: { readingStatus = $0 }
        ) {
        case .label(let parsed):
            onLabel?(parsed)
        case .food(let product):
            onFood?(product)
        case .candidates(let list):
            candidates = list
        case .menu(let items, let source):
            menuSource = source
            menuItems = items
        case .nothing(let message):
            failureMessage = message
        case .cancelled:
            break
        }
    }
}

/// The "which item?" chooser for a screenshot that listed several
/// foods (PLAN-screenshot-nutrition Part C). A confirmationDialog, not
/// a sheet, on purpose: the image doors and the scan sheet both raise
/// it, and swapping a sheet from inside a sheet is the dismissal race
/// that bit twice on 2026-07-22.
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
