import SwiftUI
import OnigiriKit

/// The shared entry door: ONE row, identical on the Log sheet and the
/// Add Food form.
///
/// **AI on**: a compact icon-only camera button beside a "Describe food
/// or meal" text field — two doors in one row (the user, 2026-08-29).
/// The field drives the host's `AIEstimateSection` the same way it
/// always has; only where its query comes from moved. This UNDOES part
/// of an earlier merge (below) on purpose: a describe field lived here
/// once, moved into the bottom `.searchable` field so the screen carried
/// only one text field, and now splits back out — but the bottom field
/// stays search-only this time, so there is still exactly one field per
/// job, just two jobs instead of one.
///
/// **The button and the field draw their OWN chip each**, not one
/// shared row card — a plain `TextField` has no visible bound of its
/// own, so the row's single grouped-list background read as ONE object
/// with a circle floating inside it, button and field blurred together
/// (the user, 2026-08-29: "doesn't look separate from the camera").
/// Giving the field the SAME `.quaternary` chip treatment the button's
/// circle already used makes them read as two controls with a gap
/// between them, not one — and freed from matching the field's own
/// (borderless, row-height) size, the button is free to be as large as
/// the row allows, so it no longer needs to punch above its actual
/// weight to be seen inside a shared card that outsized it either way.
///
/// **The field also drives online lookups now** (2026-08-29): typing
/// shows the AI estimate row AND `OnlineResultsSection` (OpenFoodFacts /
/// USDA) together, in the AI → online order the rest of the app already
/// uses. Both are tap-to-run, never per-keystroke — `TapToEstimateRow`
/// and `OnlineResultsSection`'s own "Search…" button — so combining them
/// under one field costs nothing extra. This is what makes the field's
/// gating below `isAvailable || onlineLookups` rather than `isAvailable`
/// alone: online lookups don't need AI, and hiding the field whenever AI
/// is off would strand them with no way to search.
///
/// **Neither on**: the camera button falls back to the full labeled row
/// (`ScanRowLabel`, "Scan Barcode, Label, or Menu") and the describe
/// field is hidden entirely — nothing behind it works, and a field with
/// nowhere to send its text is a dead end, not a door.
///
/// The camera button carries the SAME accessibility label the row used
/// to show as its visible title ("Scan Barcode, Label, Menu, or Food"),
/// icon-only or not — VoiceOver and `OnigiriUITests.scanRow(in:)` both
/// find it by that label, and it is still one tap to the same scanner.
struct EntryDoorsSection: View {
    /// Scan-door state owned by the host (barcode lookups etc.).
    var scanBusy = false
    /// Host-provided caption under the scan door (barcode/label/photo
    /// provenance) — nil when there's nothing to say.
    var scanCaption: String?
    /// What's typed to describe a food or meal in prose. Owned by the
    /// host so it survives this view's own remounts and so the host can
    /// drive its `AIEstimateSection` from it and clear it after a pick.
    @Binding var describeQuery: String
    let onScan: () -> Void
    /// Keyboard-submit convenience for the online leg only — matches
    /// what the retired bottom `.searchable` field did on
    /// `.onSubmit(of: .search)`. AI stays tap-only (its own button in
    /// `TapToEstimateRow`'s idle phase, one inference per tap on
    /// purpose); typing a description and hitting Return has never
    /// needed to also run inference to feel complete, but online search
    /// did offer a "just search" fast path before. `nil` = no
    /// submit-triggered search — hosts with online lookups off can skip
    /// wiring it.
    var onDescribeSubmit: (() -> Void)?

    /// Matched by the "select all on focus" notification handler in
    /// `FoodFormView` — an in-progress description must not be
    /// select-all'd out from under someone refocusing it, the same
    /// exemption the bottom search field already gets. A SwiftUI
    /// `TextField`'s accessibility identifier rides its bridged
    /// `UITextField`, which is the only handle that notification hands
    /// back.
    static let describeFieldAccessibilityID = "entryDoorsDescribeField"

    /// Whether the describe field has anything to drive — AI, online
    /// lookups, or both. `false` only when neither is on, which is the
    /// one case the field would be a dead end.
    private var describeFieldAvailable: Bool {
        FoodIntelligence.isAvailable || SharedStore.onlineLookups
    }

    var body: some View {
        Section {
            if describeFieldAvailable {
                HStack(spacing: 14) {
                    Button(action: onScan) {
                        // 44pt — LogButton's own frame, exactly, so this
                        // row's content height caps at the same place
                        // Water's does and the two pills match (the
                        // user, 2026-08-29). Larger read as its own
                        // control once the field stopped sharing its
                        // card (previous round); this is the same idea
                        // bounded by a second row it now has to agree
                        // with.
                        DoorCircleGlyph(systemImage: "camera", diameter: 44, font: .body.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(scanBusy)
                    .accessibilityLabel("Scan Barcode, Label, Menu, or Food")
                    HStack(spacing: 6) {
                        // AI ONLY, not "online lookups can search too" —
                        // the sparkle is a promise about what's behind
                        // the field, and a plain database search isn't
                        // AI (the user, 2026-08-29: "a sparkle... if AI
                        // is enabled").
                        if FoodIntelligence.isAvailable {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.riceToast)
                                .font(.callout)
                        }
                        TextField("Describe food or meal", text: $describeQuery)
                            .accessibilityLabel("Describe food or meal")
                            .accessibilityIdentifier(Self.describeFieldAccessibilityID)
                            .onSubmit { onDescribeSubmit?() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // The SAME fill `DoorCircleGlyph`'s circle uses —
                    // one "control chip" language for both, so they
                    // read as siblings rather than a button floating
                    // inside a field's own row. `.tertiarySystemGroupedBackground`,
                    // not `.quaternary` — the hierarchical material
                    // washed out light on a real device in dark mode
                    // (the user, 2026-08-30, from-device screenshot:
                    // "light mode button leak"); this is a flat,
                    // deterministic system color instead, matching
                    // `DoorCircleGlyph`'s own fix.
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Button(action: onScan) {
                    ScanRowLabel()
                }
                .disabled(scanBusy)
            }

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
