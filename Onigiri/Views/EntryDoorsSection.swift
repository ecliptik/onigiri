import SwiftUI
import OnigiriKit

// The entry doors — the camera and the "Describe food or meal" field —
// as ONE pinned bar (`EntryDoorBar`, hosted through `entryDoorBar` in
// Style.swift) under both places that create foods: the Log sheet and
// a BLANK Add Food form. History, since each turn was the user's call:
// a labeled scan row and a describe field lived in the list (2026-07);
// the describe field merged into the bottom search field, then split
// back out beside a compact camera button as an in-form chip row
// (`EntryDoorsSection`, 2026-08-29); the Log sheet's pair moved into a
// floating glass bar (2026-09-15) while the form kept its chip row; and
// on 2026-09-16 the form got the same bar ("add the camera/describe on
// the Add food dialog like the camera/describe when logging food") and
// the chip row was retired. One set of doors, one chrome, two hosts.
//
// The field drives BOTH the host's `AIEstimateSection` and its
// `OnlineResultsSection` (2026-08-29), AI → online, each tap-to-run —
// never per-keystroke — so combining them under one field costs nothing.
// That is why the field is gated on `isAvailable || onlineLookups`, not
// `isAvailable` alone: online lookups don't need AI, and hiding the
// field whenever AI is off would strand them with no way to search. When
// NEITHER is on the bar collapses to one full-width labeled camera door
// ("Scan Barcode, Label, or Menu") — a field with nowhere to send its
// text is a dead end, not a door. The Log sheet's field ALSO searches
// the library (2026-09-17, `searchesLibrary`), so there it always has
// somewhere to send its text and never collapses.

/// The camera door's button: glyph + accessibility label + the
/// disabled/action wiring, extracted so no host can say something
/// different about what a tap does. The label is the row's OLD visible
/// title, "Scan Barcode, Label, Menu, or Food", icon-only or not —
/// VoiceOver and `OnigiriUITests.scanRow(in:)` both find it by that
/// label (`label BEGINSWITH 'Scan Barcode'`).
struct EntryDoorScanButton<Content: View>: View {
    var scanBusy = false
    let onScan: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: onScan) { content() }
            .buttonStyle(.plain)
            .disabled(scanBusy)
            .accessibilityLabel("Scan Barcode, Label, Menu, or Food")
    }
}

/// The describe field itself: sparkle + `TextField` + its accessibility
/// identifier/label + submit wiring, extracted for the same reason as
/// `EntryDoorScanButton` above — `accessibilityID` is what
/// `FoodFormView`'s select-all-on-focus handler matches against, and a
/// second hand-copied field could silently stop matching it. Callers
/// wrap this in their own padding/background; it draws no chrome of its
/// own. The query is OWNED BY THE HOST (`QuickLogSheet.describeQuery`,
/// `FoodFormView.describeQuery`), separate from any search field, and
/// the host clears it on a successful pick or the estimate row lingers
/// after its job is done.
struct EntryDoorDescribeField: View {
    @Binding var describeQuery: String
    /// Keyboard-submit convenience for the ONLINE leg only — what the
    /// retired bottom `.searchable` field did on `.onSubmit(of:
    /// .search)`. AI stays tap-only (its own button in
    /// `TapToEstimateRow`'s idle phase, one inference per tap on
    /// purpose). `nil` = no submit-triggered search.
    var onDescribeSubmit: (() -> Void)?
    /// The placeholder, which doubles as the accessibility label: what
    /// the field does differs by host. The Log sheet's also searches the
    /// library, and says so (`QuickLogSheet`, 2026-09-17); the Add Food
    /// form's has no library behind it and keeps the default.
    var prompt = EntryDoorDescribeField.defaultPrompt

    static let defaultPrompt = "Describe food or meal"

    /// Matched by the "select all on focus" notification handler in
    /// `FoodFormView` — an in-progress description must not be
    /// select-all'd out from under someone refocusing it. A SwiftUI
    /// `TextField`'s accessibility identifier rides its bridged
    /// `UITextField`, which is the only handle that notification hands
    /// back. The string predates the bar; don't rename it.
    static let accessibilityID = "entryDoorsDescribeField"

    /// The HOST owns this. It started owned here — the accessory below
    /// is all the field itself needs — but the Log sheet's leading
    /// toolbar button changes with it too (2026-09-17), and a toolbar
    /// lives in the host, not down here.
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // AI ONLY, not "online lookups can search too" — the
            // sparkle is a promise about what's behind the field, and a
            // plain database search isn't AI (the user, 2026-08-29:
            // "a sparkle... if AI is enabled").
            if FoodIntelligence.isAvailable {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.riceToast)
                    .font(.callout)
            }
            // An explicit prompt in a CONCRETE color, `Color(.secondaryLabel)`,
            // not the hierarchical `.secondary`. The default placeholder
            // (tertiary) read too faint on the bar's glass capsule over
            // the dark canvas (the user, 2026-09-16: "a bit too light to
            // read on the Dark theme"), and `.secondary` still did on the
            // PHONE while looking fine on the simulator: inside
            // `glassEffect` a hierarchical style is rendered vibrant —
            // blended with the backdrop — and a dark backdrop dims it
            // again; a concrete Color is drawn as-is. Typed text stays
            // primary, so this still reads as a placeholder.
            TextField(
                prompt, text: $describeQuery,
                prompt: Text(prompt).foregroundStyle(Color(.secondaryLabel))
            )
                .accessibilityLabel(prompt)
                .accessibilityIdentifier(Self.accessibilityID)
                .focused($isFocused)
                .onSubmit { onDescribeSubmit?() }
                // Put the keyboard away without leaving the screen (the
                // user, 2026-09-17). Until this there was no way out of
                // it but Cancel or Done, which take the whole sheet with
                // them, or picking a row.
                //
                // A keyboard accessory, NOT a Cancel that turns into a
                // back button while typing: a button that changes what
                // it does under you is a mode error, it would be the one
                // escape hatch disappearing exactly when a long
                // description makes you want it, and this sheet's
                // Cancel-left/Done-right shape has been settled twice
                // (CLAUDE.md, "Food entry"). Scoped to this field's own
                // focus, so the food form's other fields are untouched.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isFocused = false }
                    }
                }
        }
    }
}

/// The camera + describe door bar (`plans/PLAN-log-sheet-layout.md`,
/// 2026-09-15): a glass-chrome pill — Liquid Glass on iOS 26+, camera
/// tinted (the app's one primary action per the HIG's "tint one, not
/// everything" rule), describe plain; the flat chip fallback below the
/// floor. PINNED via `entryDoorBar` (Style.swift) under the Log sheet's
/// List (hidden while searching) and under a blank Add Food form (hidden
/// once the form is no longer blank — a form opened from a search result
/// or editing a saved food offering another search was a loop).
///
/// In the Log sheet it spent part of 2026-09-16 as the list's trailing
/// row instead, to close the empty canvas a short Favorites list leaves
/// above a pinned bar — and was then unreachable on any real library
/// without scrolling to the very end. The user chose pinned with both
/// in hand; `entryDoorBar`'s doc comment has the rest.
struct EntryDoorBar: View {
    var scanBusy = false
    @Binding var describeQuery: String
    let onScan: () -> Void
    var onDescribeSubmit: (() -> Void)?
    /// The describe field's focus, owned by the host — see
    /// `EntryDoorDescribeField.isFocused`.
    @FocusState.Binding var describeFocused: Bool
    /// Passed through to `EntryDoorDescribeField`; see its doc comment.
    var describePrompt = EntryDoorDescribeField.defaultPrompt
    /// The host searches its LIBRARY with this field too (the Log
    /// sheet, since 2026-09-17), so the field has somewhere to send its
    /// text even with AI and online lookups both off — and must stay.
    /// The first run of `testLogWithoutSaving` after the merge (which
    /// switches online off, on a sim where AI is off) found a Log sheet
    /// with no text field at all. The form leaves this false: it has
    /// no library, and the fallback door is right for it.
    var searchesLibrary = false

    /// `searchesLibrary || isAvailable || onlineLookups`, never
    /// `isAvailable` alone (see the file header): a field with nowhere
    /// to send its text is a dead end, not a door — and a library is
    /// somewhere.
    private var describeFieldAvailable: Bool {
        searchesLibrary || FoodIntelligence.isAvailable || SharedStore.onlineLookups
    }

    var body: some View {
        Group {
            if describeFieldAvailable {
                // GlassEffectContainer: glass can't sample glass, and
                // without it the circle and the capsule fight each
                // other at 14pt apart (Liquid Glass guidance). Below
                // the floor there's no glass to coordinate, so a plain
                // HStack does the same job.
                //
                // Camera LEADING, describe field trailing — tried the
                // reverse (the user, 2026-09-16: "the camera button on
                // log is on the right of the search") and it silently
                // broke real barcode scanning: `testBarcodeLookupPrefillsForm`
                // failed twice, reproducibly, with the tap on the camera
                // never opening the scanner at all — no crash, no error,
                // just a no-op. Swapping the two views' ORDER in this
                // HStack was the only change between a passing and a
                // failing run (isolated by testing each independently);
                // the exact mechanism wasn't found (a `GlassEffectContainer`
                // hit-testing quirk when the fixed-size circle trails a
                // flexible-width field is the leading suspect, but
                // unconfirmed) and wasn't worth guessing further at
                // under time pressure. Don't reorder these two without
                // re-running that test on a device — it will not fail
                // loudly.
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 14) {
                        HStack(spacing: 14) {
                            scanControl
                            describeControl
                        }
                    }
                } else {
                    HStack(spacing: 14) {
                        scanControl
                        describeControl
                    }
                }
            } else {
                // Neither AI nor online: one full-width labeled door —
                // the field would be a dead end with nothing behind it.
                // "Menu" but not "Food": a menu document is read by the
                // deterministic table parser, open with AI off; the
                // identify cascade is not, so the label only promises
                // what it can keep.
                EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
                    fallbackLabel
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var fallbackLabel: some View {
        HStack(spacing: 10) {
            if scanBusy {
                ProgressView()
            } else {
                Image(systemName: "camera")
                    .font(.body.weight(.semibold))
            }
            Text("Scan Barcode, Label, or Menu")
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
        .modifier(DoorBarChrome(tinted: true, shape: AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
    }

    /// 50pt — matched against the rows above it (the AI estimate row,
    /// the online search row, the Water row below), which all read
    /// visibly taller than this bar's original 44pt (Apple's minimum
    /// tap target, but too skinny sitting under full-height list rows —
    /// the user, from-device screenshot, 2026-09-16). Both controls
    /// share this height so their tops and bottoms line up.
    private static let controlHeight: CGFloat = 50

    private var scanControl: some View {
        EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
            Group {
                if scanBusy {
                    ProgressView()
                } else {
                    // No explicit foreground override on 26+: glass
                    // supplies vibrant, legible content automatically
                    // (Liquid Glass guidance) — riceToast here is only
                    // for the pre-26 chip fallback, matching LogButton's
                    // circle.
                    Image(systemName: "camera")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(preGlassForeground)
                }
            }
            .frame(width: Self.controlHeight, height: Self.controlHeight)
        }
        .modifier(DoorBarChrome(tinted: true, shape: AnyShape(Circle())))
    }

    private var describeControl: some View {
        EntryDoorDescribeField(
            describeQuery: $describeQuery, onDescribeSubmit: onDescribeSubmit,
            prompt: describePrompt, isFocused: $describeFocused)
            .padding(.horizontal, 16)
            // minHeight, not a fixed height: large Dynamic Type sizes
            // need MORE than 50pt for the field's text to fit, and a
            // fixed frame would clip it.
            .frame(minHeight: Self.controlHeight)
            .modifier(DoorBarChrome(tinted: false, shape: AnyShape(Capsule())))
    }

    private var preGlassForeground: Color {
        if #available(iOS 26.0, *) { .primary } else { .riceToast }
    }
}

/// The bar's per-control chrome: Liquid Glass on iOS 26+ (tinted
/// riceToast for the camera, plain regular for the describe capsule —
/// one tint, not two, per the HIG's "when everything is tinted, nothing
/// stands out" rule); a `.tertiarySystemGroupedBackground` chip below
/// the floor — that flat system color, NOT `.quaternary`, because the
/// hierarchical material is a vibrancy style that washed out light on a
/// real device in dark mode (the user, 2026-08-30, from-device
/// screenshot: "light mode button leak"). `LogButton`'s circle has the
/// same rule for the same reason.
private struct DoorBarChrome: ViewModifier {
    var tinted: Bool
    var shape: AnyShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                tinted ? .regular.tint(.riceToast).interactive() : .regular.interactive(),
                in: shape
            )
        } else {
            content.background(Color(.tertiarySystemGroupedBackground), in: shape)
        }
    }
}
