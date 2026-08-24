import SwiftUI
import OnigiriKit

/// The step between an ESTIMATE and whatever will use it: what the read
/// found, and one field to say what it got wrong
/// (`plans/PLAN-refine-with-context.md`).
///
/// It exists because of a platform fact, not a taste for extra screens.
/// On iOS 26 the on-device model NEVER SEES the photo — `identifyFood`
/// is a relay (PLAN-identify-food): Vision names the dish, the text
/// model decomposes it into a TYPICAL serving. So the salad comes back
/// dressed, whole and average, and the one participant who knows it was
/// undressed and half eaten has no way to say so. The note is not polish
/// on the estimate; on the default engine it is the ONLY information
/// about this particular plate that ever reaches the model.
///
/// Three rules hold it together, each of them a failure paid for
/// somewhere else in the app:
///
/// - **Only ESTIMATES come here.** A printed panel delivers as it always
///   has; correcting a misread is a different job with a different
///   surface (the form, where the fields already are). It is the same
///   line the budget draws between a measurement and a verdict.
/// - **A failed refine keeps the prior estimate on screen** and says so.
///   Blanking it would cost the photograph, and by then the food is
///   eaten — the rule `MenuPickerFlow` learned as "picking the wrong row
///   must not cost the read".
/// - **The first estimate is always recoverable.** A refine that comes
///   back worse is one tap from being undone.
///
/// Compiled into the app AND the share extension, beside `MenuPicker` /
/// `MenuPickerFlow` / `LogConfirmSheet` and for the same reason: a
/// correction that behaves differently by process is one nobody can
/// predict. Plain SwiftUI and OnigiriKit only — the extension has no
/// SwiftData and no toast.
struct EstimateRefineStep: View {
    let context: RefineContext
    /// What the leading button says. "Back" where something is behind
    /// this worth returning to (the camera); "Cancel" where leaving
    /// abandons the whole read.
    var backTitle = "Back"
    let onBack: () -> Void
    let onUse: (ScannedProduct) -> Void

    /// The estimate as it stands — the prior answer until a refine
    /// replaces it, and the input to the NEXT refine, so notes
    /// accumulate ("no dressing", then "and no croutons") instead of
    /// each one being applied to the original.
    @State private var current: FoodIntelligence.RefinedFood
    @State private var note = ""
    /// The notes that actually landed, in order — the receipt for why
    /// these numbers are not the ones the camera produced.
    @State private var applied: [String] = []
    @State private var isRefining = false
    @State private var refineTask: Task<Void, Never>?
    /// Bumped per run: a completion from a superseded refine must not
    /// repaint over a newer one (`TapToEstimateRow`'s fourth behavior).
    /// Not a "did the note change" test — someone may keep typing while
    /// the model thinks, and dropping the answer for that would be a
    /// second failure mode nobody could see.
    @State private var runID = 0
    @State private var failure: String?

    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults)
    private var sodiumUnitRaw = SharedStore.unitAutomatic

    init(
        context: RefineContext,
        backTitle: String = "Back",
        onBack: @escaping () -> Void,
        onUse: @escaping (ScannedProduct) -> Void
    ) {
        self.context = context
        self.backTitle = backTitle
        self.onBack = onBack
        self.onUse = onUse
        _current = State(initialValue: context.prior)
    }

    // Content and toolbar only — the HOST supplies the
    // NavigationStack, the same division `MenuPickerFlow` uses. Two of
    // the three hosts already have a stack of their own, and nesting one
    // inside it breaks the toolbar.
    var body: some View {
        Form {
            estimateSection
            noteSection
            if !applied.isEmpty { revertSection }
        }
        .navigationTitle("Check the Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(backTitle, role: .cancel, action: onBack)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") { onUse(current.scannedProduct) }
                    .accessibilityIdentifier("refineUse")
            }
        }
        // A vanished step stops spending the user's tokens, and an
        // orphaned completion must not repaint a screen that is gone
        // (2026-07-20 audit HIGH).
        .onDisappear { refineTask?.cancel() }
    }

    // MARK: What was found

    private var estimateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(current.name)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(current.kcal, format: .number.precision(.fractionLength(0))) kcal")
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(TrackedNutrient.sodium.captionText(
                        current.sodiumMg, sodium: SodiumUnit.resolve(sodiumUnitRaw)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("refineTotals")
            }
            .padding(.vertical, 2)
            // The components ARE the evidence — what the estimate
            // assumed, itemised, so a note has something to name.
            ForEach(Array(current.components.enumerated()), id: \.offset) { _, part in
                HStack {
                    Text("\(part.portion) \(part.name)")
                    Spacer()
                    Text("\(part.kcal, format: .number.precision(.fractionLength(0))) kcal")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
            }
            if current.components.isEmpty, !current.serving.isEmpty {
                LabeledContent("Serving", value: current.serving)
                    .font(.callout)
            }
        } footer: {
            // The ✨ mark never comes off: a note makes an estimate
            // better informed, not printed.
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.engine.photoEstimateCaption)
                    // The notes that actually LANDED, on their own line
                    // — the receipt for why these numbers are not the
                    // ones the camera produced. Run together with the
                    // caption above, it read as one sentence that ended
                    // twice; outside the Label it lost the indent and
                    // hung off the sparkle's left edge.
                    if !applied.isEmpty {
                        Text("Refined with: \(applied.joined(separator: " · "))")
                    }
                }
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    // MARK: The note

    private var noteSection: some View {
        Section {
            TextField(
                "no dressing, ate half, it's tofu",
                text: $note, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("refineNote")
                .disabled(isRefining)
            if isRefining {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Refining…")
                        .foregroundStyle(.secondary)
                }
            } else {
                // A BUTTON, never per keystroke: a remote provider spends
                // the user's own tokens and the on-device model takes
                // seconds (`TapToEstimateRow`'s first rule).
                Button {
                    refine()
                } label: {
                    Label("Refine", systemImage: "arrow.trianglehead.clockwise")
                }
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("refineRun")
            }
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Add context")
        } footer: {
            Text("Say what the photo couldn't: what was left off, how much you ate, what it actually was.")
        }
    }

    private var revertSection: some View {
        Section {
            Button("Use the first estimate", role: .destructive) {
                refineTask?.cancel()
                runID += 1
                isRefining = false
                current = context.prior
                applied = []
                failure = nil
            }
            .accessibilityIdentifier("refineRevert")
        }
    }

    // MARK: Refining

    private func refine() {
        let asked = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        runID += 1
        let id = runID
        isRefining = true
        failure = nil
        refineTask?.cancel()
        refineTask = Task {
            let answer = await FoodIntelligence.refineEstimate(
                prior: current,
                grounding: context.grounding,
                note: asked,
                photo: context.image,
                orientation: context.orientation)
            guard !Task.isCancelled, id == runID else { return }
            isRefining = false
            guard let answer else {
                // NEVER a blank screen. The model declined, the network
                // went, or the answer failed the plausibility gate — the
                // estimate that was there is still the best one there is.
                failure = "Couldn't refine — the estimate is unchanged."
                return
            }
            current = answer
            applied.append(asked)
            // The note has been folded into `current`; leaving it in the
            // field would re-apply it on the next refine.
            note = ""
        }
    }
}
