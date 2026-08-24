import SwiftUI
import OnigiriKit

/// The tap-to-estimate row, shared by the food estimate (`AIEstimateSection`,
/// on Foods / the Log sheet / the food form) and the meal estimate
/// (`MealEstimateSection`, in the meal builder). One tap, ONE inference —
/// never per keystroke: remote providers spend the user's own tokens and
/// the on-device model takes seconds.
///
/// FOUR field-earned behaviors live in here, which is the whole reason this
/// type exists instead of a second copy of the machine:
///
/// 1. An edited query resets a stale result to the idle row.
/// 2. A vanished section CANCELS the in-flight inference — a dismissed
///    sheet or cleared search must stop spending the user's tokens, and an
///    orphaned completion used to repaint a stale result over the reset row.
/// 3. …but an APPEAR while still "estimating" with no live task RESUMES it:
///    tapping the row with the search keyboard up dismisses the keyboard,
///    and the List re-layout tears this section down and rebuilds it
///    milliseconds later — an onDisappear/onAppear pair with @State intact.
///    The disappear cancel killed the just-started inference and the row
///    spun forever (every provider alike; field report 2026-07-22).
/// 4. A completion whose query is no longer the one on screen is dropped.
struct TapToEstimateRow<Value, ResultRow: View>: View {
    let query: String
    /// The idle row's words. The provider NAME is the AI signal (a bare
    /// "Estimate" + sparkle didn't read as AI) and, for remote providers,
    /// the disclosure of where the typed text is about to go.
    let title: String
    /// Reported to the host so it can quiet its OTHER AI affordances while
    /// this one runs — two concurrent inferences serialize on-device and
    /// double-bill a BYO-AI provider.
    var isEstimating: Binding<Bool>?
    let estimate: (String) async -> Value?
    /// Correct a result with a note, without retyping the description
    /// (`plans/PLAN-refine-with-context.md`). "And add avocado" adds
    /// avocado to what is on screen rather than re-deriving a whole new
    /// answer whose every number has moved.
    ///
    /// nil where a host has nothing to offer — the MEAL estimate, whose
    /// components become real, individually editable foods in the form
    /// it opens.
    var refine: ((Value, String) async -> Value?)?
    @ViewBuilder let resultRow: (Value) -> ResultRow

    private enum Phase {
        case idle
        case estimating
        case result(Value)
        case failed
    }

    @State private var phase = Phase.idle
    /// The query the current phase belongs to.
    @State private var phaseQuery = ""
    @State private var estimateTask: Task<Void, Never>?
    /// The refine note, and whether one is in flight. A refine keeps the
    /// phase on `.result` — the estimate it is correcting has to stay on
    /// screen, because a failed refine leaves it standing.
    @State private var note = ""
    @State private var isRefining = false
    @State private var refineFailed = false

    @AppStorage(AIProviderSettings.enabledKey, store: SharedStore.defaults) private var aiEnabled = false
    @AppStorage(AIProviderSettings.hintDismissedKey, store: SharedStore.defaults) private var hintDismissed = false

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // AI is off by default — a one-time, dismissable pointer at the
        // switch keeps the feature discoverable without being an AI
        // affordance itself (tap the x and it never returns).
        if !aiEnabled, !hintDismissed, !trimmed.isEmpty {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.riceToast)
                    Text("AI estimates are available — turn them on in Settings → AI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        hintDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            // HIG 44 pt tap target via hit area only —
                            // the negative inset must not move layout.
                            .contentShape(Rectangle().inset(by: -14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss AI hint")
                }
            }
        }
        if FoodIntelligence.isAvailable, !trimmed.isEmpty {
            Section {
                switch phase {
                case .idle:
                    Button {
                        run(trimmed)
                    } label: {
                        // No quoted-query subtitle: the query is already
                        // visible in the search field (the user, 2026-07-20).
                        Label {
                            Text(title)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.riceToast)
                        }
                    }
                case .estimating:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Estimating…")
                            .foregroundStyle(.secondary)
                    }
                case .result(let value):
                    resultRow(value)
                    if refine != nil { refineRow(value) }
                case .failed:
                    Button {
                        run(trimmed)
                    } label: {
                        Label("Couldn't estimate — tap to try again", systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onChange(of: query) { _, updated in
                if updated.trimmingCharacters(in: .whitespaces) != phaseQuery {
                    cancel()
                    phase = .idle
                    // A stale note belongs to the estimate that just
                    // went away.
                    note = ""
                    refineFailed = false
                }
            }
            // Behavior 3 — resume, don't restart from idle: a live
            // estimating phase with no live task can only mean a
            // teardown blip killed it.
            .onAppear {
                if case .estimating = phase, estimateTask == nil {
                    run(phaseQuery)
                }
                // Behavior 3 again, for the refine: the same teardown
                // blip would leave the note row spinning forever.
                if case .result(let value) = phase, isRefining, estimateTask == nil {
                    runRefine(value)
                }
            }
            .onDisappear(perform: cancel)
        }
    }

    private func cancel() {
        estimateTask?.cancel()
        estimateTask = nil
        isEstimating?.wrappedValue = false
        isRefining = false
    }

    /// One note, one inference, one button — never per keystroke, for
    /// the reason at the top of this file.
    @ViewBuilder
    private func refineRow(_ value: Value) -> some View {
        HStack(spacing: 8) {
            TextField("Add context — \"no dressing\", \"ate half\"", text: $note)
                .disabled(isRefining)
                .accessibilityIdentifier("estimateRefineNote")
            if isRefining {
                ProgressView()
            } else {
                Button {
                    runRefine(value)
                } label: {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .foregroundStyle(Color.riceToast)
                }
                .buttonStyle(.plain)
                .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Refine estimate")
                .accessibilityIdentifier("estimateRefineRun")
            }
        }
        if refineFailed {
            // The estimate above is still the best one there is; saying
            // so beats replacing it with an error.
            Text("Couldn't refine — the estimate is unchanged.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func runRefine(_ value: Value) {
        guard let refine else { return }
        let asked = note.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty else { return }
        let query = phaseQuery
        isRefining = true
        refineFailed = false
        estimateTask?.cancel()
        isEstimating?.wrappedValue = true
        estimateTask = Task {
            let answer = await refine(value, asked)
            guard !Task.isCancelled, query == phaseQuery else { return }
            isRefining = false
            isEstimating?.wrappedValue = false
            guard let answer else {
                refineFailed = true
                return
            }
            phase = .result(answer)
            // Applied and folded in; leaving it would re-apply it next
            // time.
            note = ""
        }
    }

    private func run(_ trimmed: String) {
        phaseQuery = trimmed
        phase = .estimating
        estimateTask?.cancel()
        isEstimating?.wrappedValue = true
        estimateTask = Task {
            let value = await estimate(trimmed)
            // Behavior 4: a cancelled or superseded completion must not
            // repaint the row — the query it answered is gone. It must not
            // clear `isEstimating` either; the live task owns that flag.
            guard !Task.isCancelled, trimmed == phaseQuery else { return }
            isEstimating?.wrappedValue = false
            if let value {
                phase = .result(value)
            } else {
                phase = .failed
            }
        }
    }
}
